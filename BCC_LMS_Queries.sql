-- Question 1: Top 10 Most Popular Books by Checkout Frequency
SELECT TOP 10
    Title,
    Author,
    COUNT(*) AS Total_checkouts
FROM Checkout
GROUP BY Title, Author
ORDER BY Total_checkouts DESC;

-- Question 2: Most borrowed item types by Age
SELECT
    Age_group,
    Item_Type_Explanation,
    Total_checkouts,
	Ranks
FROM (
    SELECT
        c.Age AS Age_group,
        i.Item_Type_Explanation,
        COUNT(*) AS Total_checkouts,
		RANK() OVER (PARTITION BY c.Age ORDER BY COUNT(*) DESC) AS Ranks
    FROM Checkout c
    JOIN ItemType i ON c.item_type = i.item_type_code
    GROUP BY c.age, i.Item_Type_Explanation
) AS ranked_data
WHERE Ranks <= 5
ORDER BY Age_group, Ranks;

-- Question 3: Branches with the highest loan volumes
SELECT 
    c.Checkout_Library AS Branch_Code,
    b.Branch_Heading,
    COUNT(*) AS total_loans
FROM Branch b
LEFT JOIN Checkout c ON b.Branch_Code = c.Checkout_Library
GROUP BY c.Checkout_Library, b.Branch_Heading
ORDER BY total_loans DESC;


-- Question 4:  Language diversity in collections, apart from English
SELECT 
    Language,
     COUNT(DISTINCT Title) AS Total_items
FROM Checkout
WHERE Language != 'ENGLISH'
GROUP BY Language
ORDER BY Total_items DESC;
