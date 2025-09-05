USE BCC_LMS;
-- OVERALL ANALYSIS
--1. Checkout trend over months
WITH MonthlyData AS (
	SELECT MONTH(Date) AS Month,
	       COUNT(*) AS Total_checkouts,
	       COUNT(DISTINCT CAST(Date AS date)) AS Total_days
	FROM Checkouts
	GROUP BY MONTH(Date)
), PreviousCheckouts AS (
    SELECT *,
           LAG(Total_checkouts) OVER (ORDER BY Month) AS PrevMonthCheckouts
    FROM MonthlyData
)
SELECT Month,
       Total_checkouts,
       (Total_checkouts - PrevMonthCheckouts) * 100.0
              / NULLIF(PrevMonthCheckouts,0)AS [Percentage of change(%)],
       ROUND(Total_checkouts / Total_days, 1) AS Average_daily_checkouts
FROM PreviousCheckouts
ORDER BY Month;

--2. Top 10 most checked-out items overall
SELECT TOP 10 i.Title,
              i.Author,
              it.Item_Type_Explanation,
              COUNT(*) AS Total_checkouts
FROM Checkouts c 
JOIN Items     i  ON i.Item_Id = c.Item_Id
JOIN ItemTypes it ON it.Item_Type_Code = c.Item_Type
GROUP BY i.Title, i.Author, it.Item_Type_Explanation
ORDER BY Total_checkouts DESC, i.Title ASC;

--3. Top 3 known authors who have more than 10 checkouts for each type of item
WITH RANKEDAUTHORS AS (
	SELECT it.Item_Type_Explanation,
	       i.Author,
	       COUNT(*) AS Total_checkouts,
	       DENSE_RANK() OVER (PARTITION BY it.Item_Type_Explanation	ORDER BY COUNT(*) DESC
	) AS Rank_within_type
	FROM Checkouts c 
	JOIN Items     i  ON i.Item_Id = c.Item_Id
	JOIN ItemTypes it ON it.Item_Type_Code = c.Item_Type
	WHERE i.Author IS NOT NULL
	GROUP BY it.Item_Type_Explanation, i.Author
)
SELECT Item_Type_Explanation as Type,
       Author,
       Total_checkouts,
       Rank_within_type
FROM RankedAuthors
WHERE Rank_within_type <= 3
AND Total_checkouts > 10
ORDER BY Item_Type_Explanation, Rank_within_type, Author;

--4. Checkouts by language breakdown, excluding English.
SELECT i.Language,
              COUNT(*) AS Total_checkouts,
              FORMAT(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 'N3') AS 'Percentage(%)'
FROM Checkouts c
JOIN Items     i ON i.Item_Id = c.Item_Id
WHERE lower(i.Language) <> 'english'
GROUP BY i.Language
ORDER BY Total_checkouts DESC;

--5.	Top 10 Most/Least popular item types by checkout count.
WITH COUNTS
AS
(
	SELECT c.Item_Type,
	       i.Item_Type_Explanation,
	       COUNT(*) AS Total_checkouts
	FROM Checkouts c
	JOIN ItemTypes i ON i.Item_Type_Code = c.Item_Type
	GROUP BY c.Item_Type, i.Item_Type_Explanation
)
,    RANKS
AS
(
	SELECT *,
	       RANK() OVER (ORDER BY Total_checkouts DESC) AS Ranks
	FROM Counts
)
,    MAXRANK
AS
(
	SELECT MAX(Ranks) AS MaxRank
	FROM Ranks
)
SELECT r.*
FROM       Ranks   r
CROSS JOIN MaxRank m --As this has only 1 row
WHERE r.Ranks < 10
	OR (m.MaxRank - r.Ranks) < 10
ORDER BY r.Total_checkouts DESC;

--6.	Checkouts by age group
SELECT i.Age,
       COUNT(*) AS Total_checkouts
FROM Checkouts c
JOIN Items     i ON i.Item_Id = c.Item_Id
GROUP BY i.Age
ORDER BY Total_checkouts DESC;

--7.	Peak hour analysis — which hour in the day sees the most checkouts?
WITH HourlyCounts AS (
    SELECT 
        DATEPART(HOUR, Date) AS Hour,
        COUNT(*) AS Total_checkouts
    FROM Checkouts
    GROUP BY DATEPART(HOUR, Date)
)
SELECT 
    Hour,
    Total_checkouts,
    CASE 
        WHEN Total_checkouts > 0.75*(SELECT MAX(Total_checkouts) FROM HourlyCounts) THEN 'High Peak'
		WHEN Total_checkouts > (SELECT AVG(Total_checkouts) FROM HourlyCounts) THEN 'Peak'
        ELSE ''
    END AS Note
FROM HourlyCounts
ORDER BY Hour;

-- BRANCH ANALYSIS
SELECT
DISTINCT c.Checkout_Library, b.Branch_Heading
FROM Checkouts c
LEFT JOIN Branches  b ON c.Checkout_Library = b.Branch_Code 
ORDER BY b.Branch_Heading

-- Add missing branches into Branches table
INSERT INTO Branches (Branch_Code, Branch_Heading)
VALUES 
    ('GNGL', 'Grange 24/7 Library Locker'),
    ('LHQ',  'Library HQ'),
    ('MITL', 'Mitchelton 24/7 Library Locker'),
    ('BRRL', 'Bracken Ridge 24/7 Library Locker');

-- Adapt new branch's code into Checkouts
UPDATE Checkouts
SET Checkout_Library = CASE Checkout_Library
    WHEN 'Grange 24/7 Library Locker'        THEN 'GNGL'
    WHEN 'Mitchelton 24/7 Library Locker'    THEN 'MITL'
    WHEN 'Bracken Ridge 24/7 Library Locker' THEN 'BRRL'
    ELSE Checkout_Library
END
WHERE Checkout_Library IN (
    'Grange 24/7 Library Locker',
    'Mitchelton 24/7 Library Locker',
    'Bracken Ridge 24/7 Library Locker'
); --save time, only check affected rows

--10.	Total checkouts per branch, ranked top 10.
SELECT *
FROM (
SELECT ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS Ranks,
       b.Branch_Heading, b.Parking, b.Facilities, b.Meeting_rooms,
       COUNT(*) AS Total_checkouts
FROM Checkouts c
JOIN Branches  b ON c.Checkout_Library = b.Branch_Code
GROUP BY        b.Branch_Heading,  b.Parking, b.Facilities, b.Meeting_rooms
) AS RankedBranches
WHERE Ranks <= 10
ORDER BY Total_checkouts DESC;

--11.	Accessibility evaluation
IF OBJECT_ID('dbo.AccessibilityScore', 'FN') IS NOT NULL
    DROP FUNCTION dbo.AccessibilityScore;
GO
CREATE FUNCTION dbo.AccessibilityScore(@Parking NVARCHAR(100), @MeetingRooms BIT, @Facilities NVARCHAR(200))
RETURNS INT
AS
BEGIN
    RETURN (CASE WHEN @Parking LIKE '%Shopping%' THEN 2
                 WHEN @Parking LIKE '%Street%' THEN 1 ELSE 0 END)
         + (CASE WHEN @MeetingRooms = 1 THEN 1 ELSE 0 END)
         + (CASE WHEN @Facilities LIKE '%accessible%' THEN 2
                 WHEN @Facilities LIKE '%Limited%' THEN 1 ELSE 0 END)
END;
GO
SELECT Branch_Heading,
       Parking,
       Meeting_rooms,
       Facilities,
	   dbo.AccessibilityScore(Parking, Meeting_rooms, Facilities) AS AccessibilityPoints
FROM Branches
ORDER BY AccessibilityPoints DESC, Branch_Code;

--12.	Dynamic SQL to generate the latest 4 quarterly checkout summary for all branch
DECLARE @DynamicSQL NVARCHAR(MAX);			
DECLARE @QuarterList NVARCHAR(MAX);			-- For grouping purposes and column names

-- Prepare column names
WITH QuarterData AS (
    SELECT DISTINCT 
        CONCAT('Q', DATEPART(QUARTER, Date), '_', YEAR(Date)) AS QuarterYear,
        YEAR(Date) AS Year,
        DATEPART(QUARTER, Date) AS Quarter
    FROM Checkouts
),
LatestQuarters AS (
    SELECT TOP 4 QuarterYear 
    FROM QuarterData
    ORDER BY Year DESC, Quarter DESC
)
SELECT 
    @QuarterList = STRING_AGG(QUOTENAME(QuarterYear), ', ')
FROM LatestQuarters;

-- Construct dynamic SQL query
SET @DynamicSQL = '
SELECT Branch_Heading, ' + @QuarterList + '
FROM
(
    SELECT 
        JoinedData.Branch_Heading,  
        CONCAT(''Q'', DATEPART(QUARTER, JoinedData.Date), ''_'', YEAR(JoinedData.Date)) AS QuarterYear
    FROM (
		SELECT c.*, b.Branch_Heading
		FROM Checkouts c
		LEFT JOIN Branches  b ON c.Checkout_Library = b.Branch_Code 
	) As JoinedData

) AS SourceData
PIVOT
(
    Count(QuarterYear) FOR QuarterYear IN (' + @QuarterList + ')
) AS PivotTable
ORDER BY Branch_Heading';

-- Execute dynamic SQL query
EXEC(@DynamicSQL);


-- CUSTOM ANALYSIS
--13.	Get my books
IF OBJECT_ID(N'dbo.GetMyBooks', N'P') IS NOT NULL
    DROP PROCEDURE dbo.GetMyBooks;
GO
CREATE PROCEDURE dbo.GetMyBooks (
    @Keywords NVARCHAR(MAX)
)
AS
BEGIN
    SELECT DISTINCT
		i.Title, i.Author, i.Language, i.Age
    FROM Checkouts c
	INNER JOIN Items i
        ON c.Item_Id = i.Item_Id
    WHERE lower(i.Title) LIKE '%' + lower(@Keywords) + '%'
    ORDER BY i.Title DESC;
END;

EXEC GetMyBooks @Keywords = 'What days are for';


--14.	Get available branches
IF OBJECT_ID(N'dbo.GetAvailableBranches', N'P') IS NOT NULL
    DROP PROCEDURE dbo.GetAvailableBranches;
GO
CREATE PROCEDURE dbo.GetAvailableBranches (
    @Item_Title NVARCHAR(MAX)
)
AS
BEGIN
    SELECT 
        b.Branch_Heading,
        COUNT(c.Checkout_ID) AS Number_Of_Checkouts,
        MAX(CAST(c.Date AS DATE)) AS Last_Checkout_Date
    FROM Checkouts c
	INNER JOIN Items i
        ON c.Item_Id = i.Item_Id
    INNER JOIN Branches b
        ON c.Checkout_Library = b.Branch_Code
    WHERE i.Title = @Item_Title
    GROUP BY b.Branch_Heading
    ORDER BY Number_Of_Checkouts DESC;
END;

EXEC GetAvailableBranches @Item_Title = 'What days are for';
