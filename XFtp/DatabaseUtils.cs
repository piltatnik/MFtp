using System;
using System.Data;
using Oracle.DataAccess.Client;

namespace TransportReports
{
    class DatabaseUtils
    {
        public static OracleConnection CreateConnection(string database, string login, string password)
        {
            try
            {
                var connection = new OracleConnection()
                {
                    ConnectionString = $"USER ID={login};DATA SOURCE={database};" +
                                       $"PASSWORD=\"{password}\";PERSIST SECURITY INFO = true;"
                };
                connection.Open();
                return connection;
            }
            catch (Exception e)
            {
                throw new Exception($"Не удалось установить соединение с базой\r\n{e.Message}");
            }
        }

        public static OracleCommand GetCommand(OracleConnection conn, string query)
        {
            var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            return cmd;
        }

        public static OracleCommand GetCommand(OracleConnection conn, string query, OracleParameter[] param)
        {
            var cmd = GetCommand(conn, query);
            cmd.Parameters.AddRange(param);
            return cmd;
        }

        public static DataTable FillDataTable(OracleCommand cmd)
        {
            try
            {
                var oda = new OracleDataAdapter(cmd);
                var dt = new DataTable();
                oda.Fill(dt);
                return dt;
            }
            catch (Exception e)
            {
                Console.WriteLine($"Ошибка получения набора данных\r\n{e.Message}");
                return null;
            }
        }

        public static DataTable FillDataTable(OracleConnection conn, string query)
        {
            return FillDataTable(GetCommand(conn, query));
        }

        public static DataTable FillDataTable(OracleConnection conn, string query, OracleParameter[] param)
        {
            return FillDataTable(GetCommand(conn, query, param));
        }

        public static DataView FillDataView(OracleCommand cmd)
        {
            try
            {
                DataTable dt = FillDataTable(cmd);
                return new DataView(dt);
            }
            catch (Exception e)
            {
                Console.WriteLine($"Ошибка получения набора данных\r\n{e.Message}");
                return null;
            }
        }

        public static DataView FillDataView(OracleConnection conn, string query)
        {
            return FillDataView(GetCommand(conn, query));
        }

        public static DataView FillDataView(OracleConnection conn, string query, OracleParameter[] param)
        {
            return FillDataView(GetCommand(conn, query, param));
        }

        public static bool CallProcedure(OracleConnection conn, string storedProcName, OracleParameter[] param)
        {
            try
            {
                var cmd = GetCommand(conn, storedProcName, param);
                cmd.BindByName = true;
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.ExecuteNonQuery();
                return true;
            }
            catch (Exception e)
            {
                Console.WriteLine($"Ошибка выполнения процедуры:\r\n {e.Message}");
                return false;
            }

        }

        public static bool CallProcedure(OracleConnection conn, string storedProcName, OracleParameter[] param, OracleTransaction tran)
        {
            try
            {
                var cmd = GetCommand(conn, storedProcName, param);
                cmd.Transaction = tran;
                cmd.BindByName = true;
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.ExecuteNonQuery();
                return true;
            }
            catch (Exception e)
            {
                Console.WriteLine($"Ошибка выполнения процедуры:\r\n {e.Message}");
                return false;
            }

        }

        public static OracleDataReader GetReader(OracleConnection conn, string query)
        {
            try
            {
                var cmd = GetCommand(conn, query);
                cmd.CommandType = CommandType.Text;
                return cmd.ExecuteReader();
            }
            catch (Exception e)
            {
                Console.WriteLine($"Ошибка получения курсора:\r\n {e.Message}");
                return null;
            }
        }

        public static OracleDataReader GetReader(OracleConnection conn, string query, OracleParameter[] param)
        {
            try
            {
                var cmd = GetCommand(conn, query, param);
                cmd.CommandType = CommandType.Text;
                return cmd.ExecuteReader();
            }
            catch (Exception e)
            {
                Console.WriteLine($"Ошибка получения курсора:\r\n {e.Message}");
                return null;
            }
        }
    }
}
