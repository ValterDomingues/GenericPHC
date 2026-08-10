*==============================================================================
* example_before_after.prg
*------------------------------------------------------------------------------
* Shows a typical fragile pattern and the improved SqlToArray() approach.
* This file is documentation-by-example; prefer sql_to_array.prg in production.
*==============================================================================

* --- BEFORE (common fragile pattern) ----------------------------------------
*
* lnH = SQLCONNECT("MyDSN")
* SQLEXEC(lnH, "select * from customers where city = '" + lcCity + "'")
* DIMENSION laData[1]
* n = 0
* SELECT sqlresult
* SCAN
*   n = n + 1
*   DIMENSION laData[n]
*   laData[n] = customer_id
* ENDSCAN
* * Problems: no error checks, SQL injection, slow re-DIMENSION, no disconnect,
* *           unclear cursor name, only one field kept.
*
* --- AFTER (improved) -------------------------------------------------------

SET PROCEDURE TO sql_to_array ADDITIVE

LOCAL laRows[1], lnRows, lcErr, i, j, lnCols

lnRows = SqlToArray(@laRows, @lcErr)
IF lnRows < 0
    ? "Failed: " + lcErr
    RETURN
ENDIF

? "Rows: " + TRANSFORM(lnRows)
IF lnRows = 0
    RETURN
ENDIF

lnCols = ALEN(laRows, 2)
FOR i = 1 TO lnRows
    FOR j = 1 TO lnCols
        ?? TRANSFORM(laRows[i, j]) + CHR(9)
    ENDFOR
    ?
ENDFOR
