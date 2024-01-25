using DataReporter;
using DataReporter.dsFoldersAndFilesTableAdapters;

namespace DataReporter
{
    public partial class dsFoldersAndFiles
    {
        public partial class PrincipalRow
        {
            public string NTAccount { get { return !string.IsNullOrEmpty(this.Domain) ? $"{this.Domain}\\{this.SamAccountName}" : this.SamAccountName; } }
        }
    }
}

namespace ExtensionMethods
{
    public static class MyExtensions
    {
        public static dsFoldersAndFiles.AccessRuleRow ToAccessRuleRow(this System.Security.AccessControl.AccessRule rule)
        {
            dsFoldersAndFiles.AccessRuleRow
                row 

            return row;
        }
    }
}