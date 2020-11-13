New-IntersightApiClient "https://intersight.com/api/v1" "C:\Users\kbriney\KLB\PEI-IT-OPS\intersight.pem" "5b51f81e6a636d6d34958477/5e0f6d207564612d301d07b7/5f7b68017564612d33de8075"

$filter = "filter"
$count = "count"
$expand = "expand"
$inlinecount = "inlinecount"
$orderby = "orderby"
$select = "select"
$top = "top"
$skip = "skip"

$physicalSummaries = Invoke-ComputePhysicalSummaryApiComputePhysicalSummariesGet $false "allpages" 10 0 "RegisteredDevice.Moid eq '5a43e9297a3472366edf2a4e'"

$filter = "(RegisteredDevice.Moid eq '5a43e9297a3472366edf2a4e')"
$physicalSummaries = Invoke-ComputePhysicalSummaryApiComputePhysicalSummariesGet 


$physicalSummaries = MyComputePhysicalSummariesGet -filter $filter


$Script:ComputePhysicalSummaryApi= New-Object -TypeName intersight.Api.ComputePhysicalSummaryApi -ArgumentList @($null)

$obj = Invoke-ComputeBladeApiComputeBladesGet $false $null $null $null "Serial eq FCH241576LZ"

$filter = "RegisteredDevice.Moid eq '5a43e9297a3472366edf2a4e'"
$elementSummaries = Invoke-NetworkElementSummaryApiNetworkElementSummariesGet $false $null $null $null $filter

$filter = "Owners contains('{0}')" -f @($device.Moid)
$computePhysicalSummaries = Invoke-ComputePhysicalSummaryApiComputePhysicalSummariesGet -"`$filter" $filter
$physicalSummaries = Invoke-ComputePhysicalSummaryApiComputePhysicalSummariesGet $false "allpages" 10 0 $filter

$query = "SELECT hostname FROM host WHERE (ip = INET_ATON('{0}'));" -f @("10.247.99.13")

# Default to "Not in IPAM" until we get confirmation back from the DB...
$this.Location = "Not in IPAM"
# Write-Host $query
$dt = $Global:db.GetDataTable($query)

