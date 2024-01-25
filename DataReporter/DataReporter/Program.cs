using ExtensionMethods;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DataReporter
{
    class Program
    {
        static void Main(string[] args)
        {
            dsFoldersAndFiles
                dataset = new dsFoldersAndFiles();

            dsFoldersAndFilesTableAdapters.PrincipalTableAdapter
                taPrincipals = new DataReporter.dsFoldersAndFilesTableAdapters.PrincipalTableAdapter();
            dsFoldersAndFiles.PrincipalDataTable
                dtPrincipals = new dsFoldersAndFiles.PrincipalDataTable();

            taPrincipals.Fill(dtPrincipals);



            System.IO.DirectoryInfo
                directoryInfo = new System.IO.DirectoryInfo(@"C:\Users\kbriney");
            var
                ACL = directoryInfo.GetAccessControl();
            var
                Rules = ACL.GetAccessRules(true, true, typeof(System.Security.Principal.SecurityIdentifier));

            foreach(System.Security.AccessControl.FileSystemAccessRule rule in Rules)
            {
                dsFoldersAndFiles.PrincipalRow[]
                    k = (dsFoldersAndFiles.PrincipalRow[]) dtPrincipals.Select($"SID = '{rule.IdentityReference.Value}'");

                var
                    t = rule.ToAccessRuleRow();

                Console.WriteLine(k[0].NTAccount);

                //dsFoldersAndFiles.PrincipalDataTable
                //    dt = taPrincipals.GetPrincipalsBySID(rule.IdentityReference.Value);
            }
        }
        static System.Data.DataTable GetDataTable(MySql.Data.MySqlClient.MySqlConnection conn, String query)
        {
            System.Data.DataTable
                tmpDT = null;
            bool
                wasOpen = false;

            if (!String.IsNullOrEmpty(query))
            {
                tmpDT = new System.Data.DataTable();

                if(conn.State != System.Data.ConnectionState.Open)
                {
        
                    conn.Open();
                }
                else
                {
                    wasOpen = true;
                }

                MySql.Data.MySqlClient.MySqlCommand
                    cmd = conn.CreateCommand();

                cmd.CommandText = query;

                bool
                    completed = false;
                int
                    tries = 0;
                Random
                    rnd = new Random();

                do
                {
                    try
                    {
                        MySql.Data.MySqlClient.MySqlDataReader
                            rdr = cmd.ExecuteReader();

                        tmpDT.Load(rdr);
                        completed = true;
                    }
                    catch
                    {
                        tries++;

                        int
                            sleepMS = rnd.Next(10, 25);
                        System.Threading.Thread.Sleep(sleepMS);
                    }
                }
                while ((!completed) && (tries < 5));


                if (!wasOpen && (conn.State == System.Data.ConnectionState.Open))
                {
                    conn.Close();
                }
            }   
            else
            {
                Console.WriteLine("Empty query sent to GetDataTable!");
            }

            return tmpDT;
        }
    }
}
