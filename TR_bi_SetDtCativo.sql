/*
	After UPDATE on bi: when cativo changes to 1, store that moment in
	bi2.u_dtcativo (bi2.bi2stamp = bi.bistamp).

	u_dtcativo is written only on that transition. INSERT does not fire
	this trigger.

	SQL Server 2016 or later (CREATE OR ALTER). CREATE OR ALTER is the first
	statement of its batch.
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER TRIGGER dbo.TR_bi_SetDtCativo
ON dbo.bi
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT UPDATE(cativo)
		RETURN;

	DECLARE @agora DATETIME = GETDATE();

	UPDATE b2
		SET b2.u_dtcativo = @agora
	FROM inserted AS i
	INNER JOIN deleted AS d ON d.bistamp = i.bistamp
	INNER JOIN dbo.bi2 AS b2 ON b2.bi2stamp = i.bistamp
	WHERE i.cativo = 1
		AND ISNULL(d.cativo, 0) = 0;
END
GO
