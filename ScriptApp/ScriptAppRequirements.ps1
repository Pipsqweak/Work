# Define the requirements for the script.
#   NOTES:
#     Make sure to list requirements in dependency order.  For instance, if a validator function is to be used,
#     it must be defined prior to the requirement that uses the validator function.
$requirements = @()
<##############################################################################################################>
<##›                                                                                                        ‹##>
<##›  NOTES to maintainers.                                                                                 ‹##>
<##›     Pay special attention to the "boxed" comments.  To continue the comment within ‹#  #› and maintain ‹##>
<##›     the appearance I used special characters for "‹" and "›".  If you look closely, they are different ‹##>
<##›                                            from: "<" and ">"                                           ‹##>
<##›                                                                                                        ‹##>
<##›--------------------------------------------------------------------------------------------------------‹##>
<##›                                                                                                        ‹##>
<##› DO NOT CHANGE ANYTHING IN THE BOX.  THESE ARE REQUIRED FOR BASIC OPERATION OF THE SCRIPTAPP FRAMEWORK. ‹##>
<##› User script requirements are sourced in via Requirements.ps1 in $scriptAppPath following the           ‹##>
<##› declaration of $requirements.  Eventually I plan to implement a series of 'Requirement' classes.       ‹##>
<##›                                                                                                        ‹##>
<##›--------------------------------------------------------------------------------------------------------‹##>
<##›                                                                                                        ‹##>
<##› Log class first so [Log] is defined for the rest of the script.                                        ‹##>
<##›   Also contains the ValidatorFunction: LogLevelChecker                                                 ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "file";                                                                          <##>
<##>     FileName = $logClassScriptPath;                                                                    <##>
<##>     Description = "File containing the [Log] class."                                                   <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "type";                                                                          <##>
<##>     TypeName = "Log";                                                                                  <##>
<##>     ScriptPath = $logClassScriptPath;                                                                  <##>
<##>     Description = "Defines the [Log] class."                                                           <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "function";                                                                      <##>
<##>     FunctionName = "ScriptAppMain";                                                                    <##>
<##>     ScriptPath = $scriptMainAppPath;                                                                   <##>
<##>     Description = "Path to script containing function ScriptAppMain()."                                <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "jsonArgsfile";                                                                  <##>
<##>     FileName = $jsonArgsFile;                                                                          <##>
<##>     Description = "Path to JSON file containing run parameters."                                       <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "variable";                                                                      <##>
<##>     VariableName = "logPath";                                                                          <##>
<##>     Description = "Folder where logs will be stored."                                                  <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "path";                                                                          <##>
<##>     Create = $true;                                                                                    <##>
<##>     FromVariable = "logPath";                                                                          <##>
<##>     Description = "Folder where logs will be stored."                                                  <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##› logLevel ValidatorFunction built into [Log] class source file                                          ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "variable";                                                                      <##>
<##>     VariableName = "logLevel";                                                                         <##>
<##>     ValidatorFunction = "LogLevelChecker";                                                             <##>
<##>     DefaultValue = "WARNING";                                                                          <##>
<##>     Description = "How much logging is done."                                                          <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "variable";                                                                      <##>
<##>     VariableName = "maxLogAge";                                                                        <##>
<##>     DefaultValue = 7;                                                                                  <##>
<##>     Description = "How many days are old logs kept."                                                   <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "variable";                                                                      <##>
<##>     VariableName = "doDebug";                                                                          <##>
<##>     Description = "Execute script in debug mode?"                                                      <##>
<##>     DefaultValue = $false;                                                                             <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "variable";                                                                      <##>
<##>     VariableName = "testRun";                                                                          <##>
<##>     Description = "Execute script in test run mode?"                                                   <##>
<##>     DefaultValue = $false;                                                                             <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##> $requirements += @{                                                                                    <##>
<##>     RequirementType = "variable";                                                                      <##>
<##>     VariableName = "launchScriptAppMain";                                                              <##>
<##>     Description = "Should ScriptApp launch ScriptAppMain?"                                             <##>
<##>     DefaultValue = $true;                                                                              <##>
<##> }                                                                                                      <##>
<##›                                                                                                        ‹##>
<##############################################################################################################>
