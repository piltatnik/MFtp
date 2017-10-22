using System;
using System.Data;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using Oracle.DataAccess.Client;
using Oracle.DataAccess.Types;
using System.Xml.Serialization;
using System.Runtime.Serialization;
using TransportReports;


namespace XFtp
{
    class Program
    {
        private static string _logPath;
        private static OracleConnection _connection;
        private static string _pathSettings = "settings.xml";
        private static XftpSettings _settings;

        public static int Main(string[] args)
        {
            try
            {
                Console.WriteLine("Загрузка настроек");
                _settings = (XftpSettings)DeSerializeObject(typeof(XftpSettings), _pathSettings);
                if (!Directory.Exists(_settings.Report.Log))
                    Directory.CreateDirectory(_settings.Report.Log);
                if (!Directory.Exists(_settings.Report.Path))
                    Directory.CreateDirectory(_settings.Report.Path);

                _logPath = Path.Combine(_settings.Report.Log, $"logXFtp{DateTime.Now.ToString("ddMMyyyy_HHmmss")}.log");
                WriteLog($"Открываем лог {_logPath}...");

                if (args.Length != 1)
                    throw new Exception("В приложение ожидается передача только одного параметра.");

                WriteLog($"Номер версии исполняемого файла {Assembly.GetExecutingAssembly().GetName().Version}");
                _connection = DatabaseUtils.CreateConnection(_settings.Base.Source, _settings.Base.Login, _settings.Base.Password);
                WriteLog("Соединение с базой установлено");
                

                WriteMessages(decimal.Parse(args[0]));

                WriteLog("Закрываем лог");
                
                //Console.ReadKey();
                return 0;
            }
            catch (Exception e)
            {
                Environment.ExitCode = 1;
                if (!File.Exists(_logPath))
                {
                    Console.WriteLine("Файл лога не смог быть создан.");
                    Console.ReadLine();
                }
                else
                    WriteLog($"Выполнение программы завершается ошибкой: \r\n{e.Message}");
                Console.ReadLine();
            }
            return 666;
        }

        private static void WriteMessages(decimal slCost)
        {
            DateTime calcDate = DateTime.Now.Date.AddSeconds(-1);
            string clientsPath = Path.Combine(_settings.Report.Path,
                $"01_client_transport_{calcDate.ToString("ddMMyyyy_HHmmss")}.xml");
            string walletsPath = Path.Combine(_settings.Report.Path,
                $"02_wallet_transport_{calcDate.ToString("ddMMyyyy_HHmmss")}.xml");
            string opHistPath = Path.Combine(_settings.Report.Path,
                $"03_ophist_transport_{calcDate.ToString("ddMMyyyy_HHmmss")}.xml");

            WriteLog(
                $"Вызываем расчет сообщений на дату {calcDate.ToString("dd.MM.yyyy HH:mm:ss")}. Проезд по серии SL стоит: {slCost}");
            OracleTransaction tran = _connection.BeginTransaction();
            try
            {
                OracleParameter pDate = new OracleParameter()
                {
                    ParameterName = "pDate",
                    OracleDbType = OracleDbType.Date,
                    Value = calcDate
                }; 
                DatabaseUtils.CallProcedure(_connection, "pkg$xftp_messages.createmessages",
                    new OracleParameter[]
                    {
                        pDate,
                        new OracleParameter() { ParameterName = "pSLTravelCost", OracleDbType = OracleDbType.Decimal, Value = slCost} 
                    });

                OracleParameter pXml = new OracleParameter()
                {
                    ParameterName = "pXml",
                    OracleDbType = OracleDbType.Clob,
                    Direction = ParameterDirection.Output
                };

                DatabaseUtils.CallProcedure(_connection, "pkg$xftp_messages.getClients",
                    new OracleParameter[] {pDate, pXml});
                WriteXml(clientsPath, pXml.Value);
                
                DatabaseUtils.CallProcedure(_connection, "pkg$xftp_messages.getWallets",
                    new OracleParameter[] {pDate, pXml});
                WriteXml(walletsPath, pXml.Value);
                
                DatabaseUtils.CallProcedure(_connection, "pkg$xftp_messages.getOperationHistory",
                    new OracleParameter[] {pDate, pXml});
                WriteXml(opHistPath, pXml.Value);
                
                WriteFtp(_settings.Ftp.Path, _settings.Ftp.Login, _settings.Ftp.Password, clientsPath);
                WriteFtp(_settings.Ftp.Path, _settings.Ftp.Login, _settings.Ftp.Password, walletsPath);
                WriteFtp(_settings.Ftp.Path, _settings.Ftp.Login, _settings.Ftp.Password, opHistPath);
                tran.Commit();
            }
            catch (Exception e)
            {
                tran.Rollback();
                throw new Exception($"При формировании сообщения произошла ошибка:\r\n{e.Message}");
            }
        }


        private static void WriteLog(string str)
        {
            Console.WriteLine(str);
            try
            {
                using (var sr = File.AppendText(_logPath))
                {
                    sr.WriteLine(str);
                }
            }
            catch (Exception)
            {
                Console.WriteLine($"Ошибка записи в файл {_logPath}");
                throw new Exception($"Ошибка записи в файл {_logPath}");
            }
        }

        private static void WriteXml(string path, object value)
        {
            WriteLog($"Записываем файл {path}");
            try
            {
                if (value == DBNull.Value) return;
                TextReader tr = new StringReader(((OracleClob)value).Value);
                using (var sr = File.CreateText(path))
                {
                    sr.Write(tr.ReadToEnd());
                }
            }
            catch (Exception)
            {
                WriteLog($"Ошибка записи файла {path}");
                throw;
            }
        }

        private static void WriteFtp(string ftpRoot, string login, string password, string filePath)
        {
            var ftpPath = new Uri(new Uri(ftpRoot), Path.GetFileName(filePath)).ToString();

            FtpWebRequest request = (FtpWebRequest)WebRequest.Create(ftpPath);
            request.Method = WebRequestMethods.Ftp.UploadFile;

            request.Credentials = new NetworkCredential(login, password);
            try
            {
                StreamReader sourceStream = new StreamReader(filePath);
                byte[] fileContents = Encoding.UTF8.GetBytes(sourceStream.ReadToEnd());
                sourceStream.Close();
                request.ContentLength = fileContents.Length;

                Stream requestStream = request.GetRequestStream();
                requestStream.Write(fileContents, 0, fileContents.Length);
                requestStream.Close();

                FtpWebResponse response = (FtpWebResponse)request.GetResponse();
                WriteLog($"Файл {Path.GetFileName(filePath)} загружен на {ftpPath}");

                response.Close();
            }
            catch (Exception e)
            {
                throw new Exception($"При загрузке файла {Path.GetFileName(filePath)} на {ftpPath} произошла ошибка:\r\n{e.Message}");
            }
            

        }

        public static object DeSerializeObject(Type type, string path)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open))
                {
                    var xs = new XmlSerializer(type);
                    return xs.Deserialize(fs);
                }
            }
            catch (InvalidOperationException e)
            {
                Console.WriteLine(e.Message);
                if (e.InnerException != null)
                    Console.WriteLine(e.InnerException.Message);
            }
            catch (Exception e)
            {
                Console.WriteLine(e.Message);
            }
            throw new Exception($"Ошибка получения содержимого файла {path}");
        }
    }
}
