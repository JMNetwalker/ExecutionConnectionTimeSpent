# ExecutionConnectionTimeSpent

Execution and Connection Time Spent. This Powershell script has been designed with a main idea check the connection and execution time given some TSQL statements.
[Additional Information](https://techcommunity.microsoft.com/t5/azure-database-support-blog/lesson-learned-196-latency-and-execution-time-in-azure-sql/ba-p/3282459)

We usually work on service request that our customers want to check the spent time to connect to the database and the execution time invested on a query. In this article, I would like to share with you an example how to obtain both data. We developed this following PowerShell Script to obtain the following data:

- **How the server name is resolved.** Sometimes we could have some issues resolving the IP. 
- **Number of ports opened using** the remote port 1433 and redirect ports of Azure SQL DB and Managed Instance. 
- **By Process how to know ports** opened using the remote port 1433 and redirect ports
- **Based on this URL:**
  + **NetworkServerTime (ms)**, that returns the cumulative amount of time (in milliseconds) that the provider spent waiting for replies from the server once the application has started using the provider and has enabled statistics.
  + **Execution Time (ms)** , that Returns the cumulative amount of time (in milliseconds) that the provider has spent processing once statistics have been enabled, including the time spent waiting for replies from the server as well as the time spent executing code in the provider itself.
  + **Connection Time (ms)** , that returns the amount of time (in milliseconds) that the connection has been opened after statistics have been enabled (total connection time if statistics were enabled before opening the connection).
  + **ServerRoundTrips (ms)** , that returns the number of times the connection sent commands to the server and got a reply back once the application has started using the provider and has enabled statistics.
  + **Execution Plan** , that returns the actual execution plan used for this query. 

Basically we need to configure the parameters:

## Connectivity

- **$server** = "xxxxx.database.windows.net" // Azure SQL Server name
- **$user** = "xxxxxx" // User Name
- **$passwordSecure** = "xxxxxx" // Password
- **$Db** = "xxxxxx"      // Database Name
- **$Folder** = "C:\PerfConn" // Folder where the log file will be generated with all the issues found.
- **$PoolingQuestion** = If you want to use pooling in your connection
- **NumberOfExecution** = How many executions that you want to execute
- **$File** = That contains the TSQL file with the queries that will be executed. If the file doesn't exists or is not accesible, by default, the query to execute will be SELECT 1. See the TSQL file in this github to obtain more information.

## Outcome

- **Results.Log** = Contains all the operations and results found, including the time and execution plan in XML.

Enjoy!
