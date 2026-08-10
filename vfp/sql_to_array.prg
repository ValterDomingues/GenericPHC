*==============================================================================
* sql_to_array.prg
*------------------------------------------------------------------------------
* Improved Visual FoxPro helper: run a Microsoft SQL Server query and load
* the result into a VFP array.
*
* Usage:
*   LOCAL laRows[1], lnRows, lcErr
*   lnRows = SqlToArray(@laRows, @lcErr)
*   IF lnRows < 0
*     MESSAGEBOX(lcErr, 16, "SQL error")
*     RETURN
*   ENDIF
*
* Improvements vs. typical ad-hoc VFP snippets:
*   - SQLSTRINGCONNECT with a single connection string (easy to configure)
*   - Checks every SQLCONNECT / SQLEXEC return value
*   - Uses AERROR() for real driver messages
*   - Loads rows with COPY TO ARRAY (faster/safer than manual SCAN + DIMENSION)
*   - Always disconnects and closes the cursor (TRY/FINALLY style cleanup)
*   - Clear place to insert your SELECT
*   - Returns row count; 0 = success with empty result, <0 = failure
*==============================================================================

FUNCTION SqlToArray
LPARAMETERS taRows, tcErrorMessage
* taRows          - array passed by reference; filled with query rows
* tcErrorMessage  - character passed by reference; set on failure

LOCAL lnHandle, lnExec, lnRows, lcSql, lcConn, laErr[1]
LOCAL llCursorOpen

tcErrorMessage = ""
lnHandle = -1
llCursorOpen = .F.
lnRows = 0

*------------------------------------------------------------------------------
* Connection string — adjust server, database, and auth for your environment.
* Prefer Windows auth when possible; otherwise use UID/PWD carefully.
*------------------------------------------------------------------------------
lcConn = "Driver={SQL Server};" + ;
         "Server=YOUR_SERVER;" + ;
         "Database=YOUR_DATABASE;" + ;
         "Trusted_Connection=Yes;"
* Alternative SQL auth example:
* lcConn = "Driver={SQL Server};Server=YOUR_SERVER;Database=YOUR_DATABASE;" + ;
*          "Uid=YOUR_USER;Pwd=YOUR_PASSWORD;"

*==============================================================================
* >>> INSERT YOUR SQL QUERY HERE <<<
*------------------------------------------------------------------------------
* Keep this a SELECT that returns the columns you want in the array.
* Each row becomes one array row; columns map to array columns (2D array).
*==============================================================================
lcSql = ;
    "SELECT " + ;
    "    id, " + ;
    "    name, " + ;
    "    status " + ;
    "FROM your_table " + ;
    "WHERE status = 'pending' " + ;
    "ORDER BY id"
*==============================================================================
* End of SQL query section
*==============================================================================

TRY
    lnHandle = SQLSTRINGCONNECT(lcConn)
    IF lnHandle < 0
        AERROR(laErr)
        tcErrorMessage = "SQLSTRINGCONNECT failed: " + TransformError(laErr)
        RETURN -1
    ENDIF

    * Optional: avoid blocking the UI forever on a bad network hop
    = SQLSETPROP(lnHandle, "QueryTimeOut", 30)

    lnExec = SQLEXEC(lnHandle, lcSql, "csrSqlToArray")
    IF lnExec < 0
        AERROR(laErr)
        tcErrorMessage = "SQLEXEC failed: " + TransformError(laErr)
        RETURN -2
    ENDIF

    llCursorOpen = USED("csrSqlToArray")
    IF NOT llCursorOpen
        tcErrorMessage = "SQLEXEC succeeded but cursor csrSqlToArray was not created."
        RETURN -3
    ENDIF

    SELECT csrSqlToArray
    lnRows = RECCOUNT()

    IF lnRows = 0
        * Empty result: expose a 0-row array cleanly for the caller
        DIMENSION taRows[1]
        taRows[1] = .F.
        RETURN 0
    ENDIF

    * Best practice: let VFP build the array in one shot from the cursor.
    * Result is a 2D array: taRows[row, column]
    COPY TO ARRAY taRows
    RETURN lnRows

CATCH TO loEx
    tcErrorMessage = "Unexpected error: " + loEx.Message
    RETURN -9

FINALLY
    IF llCursorOpen AND USED("csrSqlToArray")
        USE IN SELECT("csrSqlToArray")
    ENDIF
    IF lnHandle > 0
        = SQLDISCONNECT(lnHandle)
    ENDIF
ENDTRY
ENDFUNC


FUNCTION TransformError
LPARAMETERS taErr
* AERROR() layout: [1]=number, [2]=message, [3]=object, [4]=workarea/handle, ...
IF TYPE("taErr[1]") = "U" OR ALEN(taErr, 1) < 2
    RETURN "Unknown SQL error"
ENDIF
RETURN ALLTRIM(TRANSFORM(taErr[1])) + " - " + ALLTRIM(TRANSFORM(taErr[2]))
ENDFUNC
