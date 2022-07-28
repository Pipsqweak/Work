$ipBlockTestCases = @(
    @{errorMsg = "Good test";                        testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Bad IP Pool";                      testCase = @{ucs = $ucsPE; ipPoolName = "extmgmt";  fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }}, # Non-existant IP Pool
    @{errorMsg = "From to reverse -- good test";     testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.75"; toAddress = "192.168.1.50"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Invalid subnet mask";              testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "254.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Primary and secondary DNS match";  testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.20"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Primary DNS in from-to range";     testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.60"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Secondary DNS in from-to range";   testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.60"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "From-To in different subnets";     testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.2.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Default gate in different subnet"; testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.3.1" }},
    @{errorMsg = "Invalid from";                     testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.43";   toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Invalid to";                       testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "6";            subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Invalid subnet mask #2";           testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "dumb";          primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Invalid primary DNS";              testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "5.g.2.t";      secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Invalid secondary DNS";            testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "craptastic";   defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Invalid default gateway";          testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.50"; toAddress = "192.168.1.75"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "256.168.1.1" }},
    @{errorMsg = "Overlap 1";                        testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.55"; toAddress = "192.168.1.90"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Overlap 2";                        testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.45"; toAddress = "192.168.1.60"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }},
    @{errorMsg = "Overlap 3";                        testCase = @{ucs = $ucsPE; ipPoolName = "ext-mgmt"; fromAddress = "192.168.1.40"; toAddress = "192.168.1.90"; subnetMask = "255.255.255.0"; primaryDNS = "192.168.1.20"; secondaryDNS = "192.168.1.30"; defaultGateway = "192.168.1.1" }}
)

foreach($ipBlockTestCase in $ipBlockTestCases)
{
    $testCase = $ipBlockTestCase.testCase

    if (-not (CreateIPBlock @testCase))
    {
        # TRUE

        Write-Host $ipBlockTestCase.errorMsg
    }
    else # NOT (-not (CreateIPBlock @testCase))
    {
        # FALSE

        # Nothing.
    }
}
