using DNSTest;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using static DNSTest.DNSServer;

namespace DNSTest
{
    internal class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Hello, World!");


            Console.Write("Connecting to the DNS Server...");
            DNSServer d = new DNSServer("boidc01.powereng.com"); //my internal DNS Server, change to yours.
                                                                 //You will need to be able to get to it using WMI.
            Console.WriteLine("Connected to the DNS Server");

            Console.Write("Creating a new zone as a test...");
            /*
            try
            {
                d.CreateNewZone("testzone.uk.nullify.net.", DNSServer.NewZoneType.Primary);
                Console.WriteLine("OK");
            }
            catch (Exception)
            {
                Console.WriteLine("Failed to create a new zone, it probably exists.");
            }

            Console.Write("Creating a DNS record as a test...");
            try
            {
                d.CreateDNSRecord("testzone.uk.nullify.net.", "test1.testzone.uk.nullify.net. IN CNAME xerxes.nullify.net.");
                Console.WriteLine("OK");
            }
            catch (Exception)
            {
                Console.WriteLine("Failed to create a new resource record, it probably exists");
            }
            */

            Console.WriteLine("Getting a list of domains:");
            foreach (DNSServer.DNSDomain domain in d.GetListOfDomains())
            {
                Console.WriteLine("\t" + domain.Name + " (" + domain.ZoneType + ")");
                //and a list of all the records in the domain:-
//                foreach (DNSServer.DNSRecord record in d.GetRecordsForDomain(domain.Name))
//                {
//                    Console.WriteLine("\t\t" + record);
                    //any domains we are primary for we could go and edit the record now!
//                }
            }

            DNSRecord[]
                PEIRecords = d.GetHostPTRRecord("boidc01.powereng.com");

//            Console.WriteLine("Fetching existing named entry (can be really slow, read the warning):-");
//            DNSServer.DNSRecord[] records = d.GetExistingDNSRecords("se4-ucs01.powereng.com.");
//            foreach (DNSServer.DNSRecord record in records)
//            {
//                Console.WriteLine("\t\t" + record);
//            }
        }
    }
}



