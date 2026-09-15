# Open `u_reccli` from the last 2 business days

Drop-in replacement for the user-filtered open-incidence list (`fechada=0`),
with `u_reccli.data` limited to the **last 2 weekdays**.

`sql/u_reccli_open_last_2_business_days.sql`

Business days here are Monday–Friday. Public holidays are not removed (there
is no holiday table in this query). `DATEDIFF(DAY, 0, @mToday) % 7` is used so
the weekday does not depend on `SET DATEFIRST`.

| Today | Rows with `data` from … to … |
| --- | --- |
| Monday | Friday … Monday |
| Tuesday–Friday | yesterday … today |
| Saturday or Sunday | Thursday … Friday |

The extra predicate sits next to `fechada=0` in the inner `u_reccli` subquery:

```sql
AND CONVERT(DATE, u_reccli.data) >= @mFrom
AND CONVERT(DATE, u_reccli.data) <= @mTo
```
