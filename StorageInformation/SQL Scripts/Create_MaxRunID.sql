
CREATE FUNCTION MaxRunID()
RETURNS int
AS
BEGIN
	-- Declare the return variable here
	DECLARE @MaxRunID int;

	-- Add the T-SQL statements to compute the return value here
	SELECT @MaxRunID = MAX(ID) FROM DataCollectionRuns;

	-- Return the result of the function
	RETURN @MaxRunId

END
GO

