# Condensed version of PowerView that allows the user to run several important domain checks
# quickly when they get onto a box by using the 'Get-DomainInfo' command

function New-InMemoryModule
{
    Param
    (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ModuleName = [Guid]::NewGuid().ToString()
    )

    $LoadedAssemblies = [AppDomain]::CurrentDomain.GetAssemblies()

    foreach ($Assembly in $LoadedAssemblies) {
        if ($Assembly.FullName -and ($Assembly.FullName.Split(',')[0] -eq $ModuleName)) {
            return $Assembly
        }
    }

    $DynAssembly = New-Object Reflection.AssemblyName($ModuleName)
    $Domain = [AppDomain]::CurrentDomain
    $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, 'Run')
    $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule($ModuleName, $False)

    return $ModuleBuilder
}

function func
{
    Param
    (
        [Parameter(Position = 0, Mandatory = $True)]
        [String]
        $DllName,

        [Parameter(Position = 1, Mandatory = $True)]
        [string]
        $FunctionName,

        [Parameter(Position = 2, Mandatory = $True)]
        [Type]
        $ReturnType,

        [Parameter(Position = 3)]
        [Type[]]
        $ParameterTypes,

        [Parameter(Position = 4)]
        [Runtime.InteropServices.CallingConvention]
        $NativeCallingConvention,

        [Parameter(Position = 5)]
        [Runtime.InteropServices.CharSet]
        $Charset,

        [Switch]
        $SetLastError
    )

    $Properties = @{
        DllName = $DllName
        FunctionName = $FunctionName
        ReturnType = $ReturnType
    }

    if ($ParameterTypes) { $Properties['ParameterTypes'] = $ParameterTypes }
    if ($NativeCallingConvention) { $Properties['NativeCallingConvention'] = $NativeCallingConvention }
    if ($Charset) { $Properties['Charset'] = $Charset }
    if ($SetLastError) { $Properties['SetLastError'] = $SetLastError }

    New-Object PSObject -Property $Properties
}


function Add-Win32Type
{
    [OutputType([Hashtable])]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)]
        [String]
        $DllName,

        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)]
        [String]
        $FunctionName,

        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)]
        [Type]
        $ReturnType,

        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [Type[]]
        $ParameterTypes,

        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [Runtime.InteropServices.CallingConvention]
        $NativeCallingConvention = [Runtime.InteropServices.CallingConvention]::StdCall,

        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [Runtime.InteropServices.CharSet]
        $Charset = [Runtime.InteropServices.CharSet]::Auto,

        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [Switch]
        $SetLastError,

        [Parameter(Mandatory = $True)]
        [ValidateScript({($_ -is [Reflection.Emit.ModuleBuilder]) -or ($_ -is [Reflection.Assembly])})]
        $Module,

        [ValidateNotNull()]
        [String]
        $Namespace = ''
    )

    BEGIN
    {
        $TypeHash = @{}
    }

    PROCESS
    {
        if ($Module -is [Reflection.Assembly])
        {
            if ($Namespace)
            {
                $TypeHash[$DllName] = $Module.GetType("$Namespace.$DllName")
            }
            else
            {
                $TypeHash[$DllName] = $Module.GetType($DllName)
            }
        }
        else
        {
            # Define one type for each DLL
            if (!$TypeHash.ContainsKey($DllName))
            {
                if ($Namespace)
                {
                    $TypeHash[$DllName] = $Module.DefineType("$Namespace.$DllName", 'Public,BeforeFieldInit')
                }
                else
                {
                    $TypeHash[$DllName] = $Module.DefineType($DllName, 'Public,BeforeFieldInit')
                }
            }

            $Method = $TypeHash[$DllName].DefineMethod(
                $FunctionName,
                'Public,Static,PinvokeImpl',
                $ReturnType,
                $ParameterTypes)

            # Make each ByRef parameter an Out parameter
            $i = 1
            foreach($Parameter in $ParameterTypes)
            {
                if ($Parameter.IsByRef)
                {
                    [void] $Method.DefineParameter($i, 'Out', $null)
                }

                $i++
            }

            $DllImport = [Runtime.InteropServices.DllImportAttribute]
            $SetLastErrorField = $DllImport.GetField('SetLastError')
            $CallingConventionField = $DllImport.GetField('CallingConvention')
            $CharsetField = $DllImport.GetField('CharSet')
            if ($SetLastError) { $SLEValue = $True } else { $SLEValue = $False }

            # Equivalent to C# version of [DllImport(DllName)]
            $Constructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor([String])
            $DllImportAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($Constructor,
                $DllName, [Reflection.PropertyInfo[]] @(), [Object[]] @(),
                [Reflection.FieldInfo[]] @($SetLastErrorField, $CallingConventionField, $CharsetField),
                [Object[]] @($SLEValue, ([Runtime.InteropServices.CallingConvention] $NativeCallingConvention), ([Runtime.InteropServices.CharSet] $Charset)))

            $Method.SetCustomAttribute($DllImportAttribute)
        }
    }

    END
    {
        if ($Module -is [Reflection.Assembly])
        {
            return $TypeHash
        }

        $ReturnTypes = @{}

        foreach ($Key in $TypeHash.Keys)
        {
            $Type = $TypeHash[$Key].CreateType()

            $ReturnTypes[$Key] = $Type
        }

        return $ReturnTypes
    }
}


function psenum
{
    [OutputType([Type])]
    Param
    (
        [Parameter(Position = 0, Mandatory = $True)]
        [ValidateScript({($_ -is [Reflection.Emit.ModuleBuilder]) -or ($_ -is [Reflection.Assembly])})]
        $Module,

        [Parameter(Position = 1, Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FullName,

        [Parameter(Position = 2, Mandatory = $True)]
        [Type]
        $Type,

        [Parameter(Position = 3, Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $EnumElements,

        [Switch]
        $Bitfield
    )

    if ($Module -is [Reflection.Assembly])
    {
        return ($Module.GetType($FullName))
    }

    $EnumType = $Type -as [Type]

    $EnumBuilder = $Module.DefineEnum($FullName, 'Public', $EnumType)

    if ($Bitfield)
    {
        $FlagsConstructor = [FlagsAttribute].GetConstructor(@())
        $FlagsCustomAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($FlagsConstructor, @())
        $EnumBuilder.SetCustomAttribute($FlagsCustomAttribute)
    }

    foreach ($Key in $EnumElements.Keys)
    {
        # Apply the specified enum type to each element
        $null = $EnumBuilder.DefineLiteral($Key, $EnumElements[$Key] -as $EnumType)
    }

    $EnumBuilder.CreateType()
}


# A helper function used to reduce typing while defining struct
# fields.
function field
{
    Param
    (
        [Parameter(Position = 0, Mandatory = $True)]
        [UInt16]
        $Position,

        [Parameter(Position = 1, Mandatory = $True)]
        [Type]
        $Type,

        [Parameter(Position = 2)]
        [UInt16]
        $Offset,

        [Object[]]
        $MarshalAs
    )

    @{
        Position = $Position
        Type = $Type -as [Type]
        Offset = $Offset
        MarshalAs = $MarshalAs
    }
}


function struct
{
    [OutputType([Type])]
    Param
    (
        [Parameter(Position = 1, Mandatory = $True)]
        [ValidateScript({($_ -is [Reflection.Emit.ModuleBuilder]) -or ($_ -is [Reflection.Assembly])})]
        $Module,

        [Parameter(Position = 2, Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FullName,

        [Parameter(Position = 3, Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $StructFields,

        [Reflection.Emit.PackingSize]
        $PackingSize = [Reflection.Emit.PackingSize]::Unspecified,

        [Switch]
        $ExplicitLayout
    )

    if ($Module -is [Reflection.Assembly])
    {
        return ($Module.GetType($FullName))
    }

    [Reflection.TypeAttributes] $StructAttributes = 'AnsiClass,
        Class,
        Public,
        Sealed,
        BeforeFieldInit'

    if ($ExplicitLayout)
    {
        $StructAttributes = $StructAttributes -bor [Reflection.TypeAttributes]::ExplicitLayout
    }
    else
    {
        $StructAttributes = $StructAttributes -bor [Reflection.TypeAttributes]::SequentialLayout
    }

    $StructBuilder = $Module.DefineType($FullName, $StructAttributes, [ValueType], $PackingSize)
    $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]
    $SizeConst = @([Runtime.InteropServices.MarshalAsAttribute].GetField('SizeConst'))

    $Fields = New-Object Hashtable[]($StructFields.Count)

    # Sort each field according to the orders specified
    # Unfortunately, PSv2 doesn't have the luxury of the
    # hashtable [Ordered] accelerator.
    foreach ($Field in $StructFields.Keys)
    {
        $Index = $StructFields[$Field]['Position']
        $Fields[$Index] = @{FieldName = $Field; Properties = $StructFields[$Field]}
    }

    foreach ($Field in $Fields)
    {
        $FieldName = $Field['FieldName']
        $FieldProp = $Field['Properties']

        $Offset = $FieldProp['Offset']
        $Type = $FieldProp['Type']
        $MarshalAs = $FieldProp['MarshalAs']

        $NewField = $StructBuilder.DefineField($FieldName, $Type, 'Public')

        if ($MarshalAs)
        {
            $UnmanagedType = $MarshalAs[0] -as ([Runtime.InteropServices.UnmanagedType])
            if ($MarshalAs[1])
            {
                $Size = $MarshalAs[1]
                $AttribBuilder = New-Object Reflection.Emit.CustomAttributeBuilder($ConstructorInfo,
                    $UnmanagedType, $SizeConst, @($Size))
            }
            else
            {
                $AttribBuilder = New-Object Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, [Object[]] @($UnmanagedType))
            }

            $NewField.SetCustomAttribute($AttribBuilder)
        }

        if ($ExplicitLayout) { $NewField.SetOffset($Offset) }
    }

    # Make the struct aware of its own size.
    # No more having to call [Runtime.InteropServices.Marshal]::SizeOf!
    $SizeMethod = $StructBuilder.DefineMethod('GetSize',
        'Public, Static',
        [Int],
        [Type[]] @())
    $ILGenerator = $SizeMethod.GetILGenerator()
    # Thanks for the help, Jason Shirk!
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Ldtoken, $StructBuilder)
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Call,
        [Type].GetMethod('GetTypeFromHandle'))
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Call,
        [Runtime.InteropServices.Marshal].GetMethod('SizeOf', [Type[]] @([Type])))
    $ILGenerator.Emit([Reflection.Emit.OpCodes]::Ret)

    # Allow for explicit casting from an IntPtr
    # No more having to call [Runtime.InteropServices.Marshal]::PtrToStructure!
    $ImplicitConverter = $StructBuilder.DefineMethod('op_Implicit',
        'PrivateScope, Public, Static, HideBySig, SpecialName',
        $StructBuilder,
        [Type[]] @([IntPtr]))
    $ILGenerator2 = $ImplicitConverter.GetILGenerator()
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Nop)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Ldtoken, $StructBuilder)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Call,
        [Type].GetMethod('GetTypeFromHandle'))
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Call,
        [Runtime.InteropServices.Marshal].GetMethod('PtrToStructure', [Type[]] @([IntPtr], [Type])))
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Unbox_Any, $StructBuilder)
    $ILGenerator2.Emit([Reflection.Emit.OpCodes]::Ret)

    $StructBuilder.CreateType()
}


function Get-ShuffledArray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$True)]
        [Array]$Array
    )
    Begin{}
    Process{
        $len = $Array.Length
        while($len){
            $i = Get-Random ($len --)
            $tmp = $Array[$len]
            $Array[$len] = $Array[$i]
            $Array[$i] = $tmp
        }
        $Array;
    }
}

function Get-HostIP {
    [CmdletBinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string]
        $hostname = ''
    )
    process {
        try{
            # get the IP resolution of this specified hostname
            $results = @(([net.dns]::GetHostEntry($hostname)).AddressList)

            if ($results.Count -ne 0){
                foreach ($result in $results) {
                    # make sure the returned result is IPv4
                    if ($result.AddressFamily -eq 'InterNetwork') {
                        $result.IPAddressToString
                    }
                }
            }
        }
        catch{
            Write-Verbose -Message 'Could not resolve host to an IP Address.'
        }
    }
    end {}
}

function Test-Server {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$true)]
        [String]
        $Server,

        [Switch]
        $RPC
    )

    process {
        if ($RPC){
            $WMIParameters = @{
                            namespace = 'root\cimv2'
                            Class = 'win32_ComputerSystem'
                            ComputerName = $Name
                            ErrorAction = 'Stop'
                          }
            if ($Credential -ne $null)
            {
                $WMIParameters.Credential = $Credential
            }
            try
            {
                Get-WmiObject @WMIParameters
            }
            catch {
                Write-Verbose -Message 'Could not connect via WMI'
            }
        }
        # otherwise, use ping
        else{
            Test-Connection -ComputerName $Server -count 1 -Quiet
        }
    }
}

function Convert-SidToName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$True)]
        [String]
        $SID
    )

    process {
        try {
            $obj = (New-Object System.Security.Principal.SecurityIdentifier($SID))
            $obj.Translate( [System.Security.Principal.NTAccount]).Value
        }
        catch {
            Write-Warning "invalid SID"
        }
    }
}


function Translate-NT4Name {
    [CmdletBinding()]
    param(
        [String] $DomainObject,
        [String] $Domain
    )

    if (-not $Domain) {
        $domain = (Get-NetDomain).name
    }

    $DomainObject = $DomainObject -replace "/","\"

    # Accessor functions to simplify calls to NameTranslate
    function Invoke-Method([__ComObject] $object, [String] $method, $parameters) {
        $output = $object.GetType().InvokeMember($method, "InvokeMethod", $NULL, $object, $parameters)
        if ( $output ) { $output }
    }
    function Set-Property([__ComObject] $object, [String] $property, $parameters) {
        [Void] $object.GetType().InvokeMember($property, "SetProperty", $NULL, $object, $parameters)
    }

    $Translate = new-object -comobject NameTranslate

    try {
        Invoke-Method $Translate "Init" (1, $Domain)
    }
    catch [System.Management.Automation.MethodInvocationException] { }

    Set-Property $Translate "ChaseReferral" (0x60)

    try {
        Invoke-Method $Translate "Set" (3, $DomainObject)
        (Invoke-Method $Translate "Get" (2))
    }
    catch [System.Management.Automation.MethodInvocationException] { }
}

function Get-NetDomain {

    [CmdletBinding()]
    param(
        [String]
        $Domain
    )

    if($Domain -and ($Domain -ne "")){
        $DomainContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $Domain)
        try {
            [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContext)
        }
        catch{
            Write-Warning "The specified domain $Domain does not exist, could not be contacted, or there isn't an existing trust."
            $Null
        }
    }
    else{
        [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    }
}

function Get-NetForest {
    [CmdletBinding()]
    param(
        [string]
        $Forest
    )

    if($Forest){
        # if a forest is specified, try to grab that forest
        $ForestContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Forest', $Forest)
        try{
            [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ForestContext)
        }
        catch{
            Write-Warning "The specified forest $Forest does not exist, could not be contacted, or there isn't an existing trust."
            $Null
        }
    }
    else{
        # otherwise use the current forest
        [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
    }
}

function Get-NetForestDomains {
    [CmdletBinding()]
    param(
        [string]
        $Domain,

        [string]
        $Forest
    )

    if($Domain){
        # try to detect a wild card so we use -like
        if($Domain.Contains('*')){
            (Get-NetForest -Forest $Forest).Domains | Where-Object {$_.Name -like $Domain}
        }
        else{
            # match the exact domain name if there's not a wildcard
            (Get-NetForest -Forest $Forest).Domains | Where-Object {$_.Name.ToLower() -eq $Domain.ToLower()}
        }
    }
    else{
        # return all domains
        (Get-NetForest -Forest $Forest).Domains
    }
}

function Get-NetDomainControllers {
    [CmdletBinding()]
    param(
        [string]
        $Domain
    )

    $d = Get-NetDomain -Domain $Domain
    if($d){
        $d.DomainControllers
    }
}

function Get-NetCurrentUser {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Get-NameField {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$True)]
        $object
    )
    process {
        if($object){
            if ( [bool]($object.PSobject.Properties.name -match "dnshostname") ) {
                # objects from Get-NetComputers
                $object.dnshostname
            }
            elseif ( [bool]($object.PSobject.Properties.name -match "name") ) {
                # objects from Get-NetDomainControllers
                $object.name
            }
            else {
                # strings and catch alls
                $object
            }
        }
        else{
            return $Null
        }
    }
}


function Get-NetUser {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$True)]
        [string]
        $UserName,

        [string]
        $OU,

        [string]
        $Filter,

        [string]
        $Domain
    )
    process {
        # if a domain is specified, try to grab that domain
        if ($Domain){

            # try to grab the primary DC for the current domain
            try{
                $PrimaryDC = ([Array](Get-NetDomainControllers))[0].Name
            }
            catch{
                $PrimaryDC = $Null
            }

            try {
                # reference - http://blogs.msdn.com/b/javaller/archive/2013/07/29/searching-across-active-directory-domains-in-powershell.aspx
                $dn = "DC=$($Domain.Replace('.', ',DC='))"

                # if we have an OU specified, be sure to through it in
                if($OU){
                    $dn = "OU=$OU,$dn"
                }

                # if we could grab the primary DC for the current domain, use that for the query
                if ($PrimaryDC){
                    $UserSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$PrimaryDC/$dn")
                }
                else{
                    # otherwise try to connect to the DC for the target domain
                    $UserSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dn")
                }

                # check if we're using a username filter or not
                if($UserName){
                    # samAccountType=805306368 indicates user objects
                    $UserSearcher.filter="(&(samAccountType=805306368)(samAccountName=$UserName))"
                }
                elseif($Filter){
                    # filter is something like (samAccountName=*blah*)
                    $UserSearcher.filter="(&(samAccountType=805306368)$Filter)"
                }
                else{
                    $UserSearcher.filter='(&(samAccountType=805306368))'
                }
                $UserSearcher.PageSize = 200
                $UserSearcher.FindAll() | ForEach-Object {
                    # for each user/member, do a quick adsi object grab
                    $properties = $_.Properties
                    $out = New-Object psobject
                    $properties.PropertyNames | % {
                        if ($_ -eq "objectsid"){
                            # convert the SID to a string
                            $out | Add-Member Noteproperty $_ ((New-Object System.Security.Principal.SecurityIdentifier($properties[$_][0],0)).Value)
                        }
                        elseif($_ -eq "objectguid"){
                            # convert the GUID to a string
                            $out | Add-Member Noteproperty $_ (New-Object Guid (,$properties[$_][0])).Guid
                        }
                        elseif( ($_ -eq "lastlogon") -or ($_ -eq "lastlogontimestamp") -or ($_ -eq "pwdlastset") ){
                            $out | Add-Member Noteproperty $_ ([datetime]::FromFileTime(($properties[$_][0])))
                        }
                        else {
                            if ($properties[$_].count -eq 1) {
                                $out | Add-Member Noteproperty $_ $properties[$_][0]
                            }
                            else {
                                $out | Add-Member Noteproperty $_ $properties[$_]
                            }
                        }
                    }
                    $out
                }
            }
            catch{
                Write-Warning "The specified domain $Domain does not exist, could not be contacted, or there isn't an existing trust."
            }
        }
        else{
            # otherwise, use the current domain
            if($UserName){
                $UserSearcher = [adsisearcher]"(&(samAccountType=805306368)(samAccountName=*$UserName*))"
            }
            # if we're specifying an OU
            elseif($OU){
                $dn = "OU=$OU," + ([adsi]'').distinguishedname
                $UserSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dn")
                $UserSearcher.filter='(&(samAccountType=805306368))'
            }
            # if we're specifying a specific LDAP query string
            elseif($Filter){
                # filter is something like (samAccountName=*blah*)
                $UserSearcher = [adsisearcher]"(&(samAccountType=805306368)$Filter)"
            }
            else{
                $UserSearcher = [adsisearcher]'(&(samAccountType=805306368))'
            }
            $UserSearcher.PageSize = 200

            $UserSearcher.FindAll() | ForEach-Object {
                # for each user/member, do a quick adsi object grab
                $properties = $_.Properties
                $out = New-Object psobject
                $properties.PropertyNames | % {
                    if ($_ -eq "objectsid"){
                        # convert the SID to a string
                        $out | Add-Member Noteproperty $_ ((New-Object System.Security.Principal.SecurityIdentifier($properties[$_][0],0)).Value)
                    }
                    elseif($_ -eq "objectguid"){
                        # convert the GUID to a string
                        $out | Add-Member Noteproperty $_ (New-Object Guid (,$properties[$_][0])).Guid
                    }
                    elseif( ($_ -eq "lastlogon") -or ($_ -eq "lastlogontimestamp") -or ($_ -eq "pwdlastset") ){
                        $out | Add-Member Noteproperty $_ ([datetime]::FromFileTime(($properties[$_][0])))
                    }
                    else {
                        if ($properties[$_].count -eq 1) {
                            $out | Add-Member Noteproperty $_ $properties[$_][0]
                        }
                        else {
                            $out | Add-Member Noteproperty $_ $properties[$_]
                        }
                    }
                }
                $out
            }
        }
    }
}


function Get-NetUserSPNs {

    [CmdletBinding()]
    param(
        [string]
        $UserName,

        [string]
        $Domain
    )


    # if a domain is specified, try to grab that domain
    if ($Domain){

        # try to grab the primary DC for the current domain
        try{
            $PrimaryDC = ([Array](Get-NetDomainControllers))[0].Name
        }
        catch{
            $PrimaryDC = $Null
        }

        try {
            # reference - http://blogs.msdn.com/b/javaller/archive/2013/07/29/searching-across-active-directory-domains-in-powershell.aspx
            $dn = "DC=$($Domain.Replace('.', ',DC='))"

            # if we could grab the primary DC for the current domain, use that for the query
            if ($PrimaryDC){
                $UserSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$PrimaryDC/$dn")
            }
            else{
                # otherwise try to connect to the DC for the target domain
                $UserSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dn")
            }

            # check if we're using a username filter or not
            if($UserName){
                # samAccountType=805306368 indicates user objects
                $UserSearcher.filter="(&(samAccountType=805306368)(samAccountName=$UserName))"
            }
            else{
                $UserSearcher.filter='(&(samAccountType=805306368))'
            }
            $UserSearcher.FindAll() | ForEach-Object {
                if ($_.properties['ServicePrincipalName'].count -gt 0){
                    $out = New-Object psobject
                    $out | Add-Member Noteproperty 'SamAccountName' $_.properties.samaccountname
                    $out | Add-Member Noteproperty 'ServicePrincipalName' $_.properties['ServicePrincipalName']
                    $out
                }
            }
        }
        catch{
            Write-Warning "The specified domain $Domain does not exist, could not be contacted, or there isn't an existing trust."
        }
    }
    else{
        # otherwise, use the current domain
        if($UserName){
            $UserSearcher = [adsisearcher]"(&(samAccountType=805306368)(samAccountName=*$UserName*))"
        }
        else{
            $UserSearcher = [adsisearcher]'(&(samAccountType=805306368))'
        }
        $UserSearcher.FindAll() | ForEach-Object {
            if ($_.properties['ServicePrincipalName'].count -gt 0){
                $out = New-Object psobject
                $out | Add-Member Noteproperty 'samaccountname' $_.properties.samaccountname
                $out | Add-Member Noteproperty 'ServicePrincipalName' $_.properties['ServicePrincipalName']
                $out
            }
        }
    }
}

function Get-NetComputers {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline=$True)]
        [string]
        $HostName = '*',

        [string]
        $SPN = '*',

        [string]
        $OperatingSystem = '*',

        [string]
        $ServicePack = '*',

        [Switch]
        $Ping,

        [Switch]
        $FullData,

        [string]
        $Domain
    )

    process {
        # if a domain is specified, try to grab that domain
        if ($Domain){

            # try to grab the primary DC for the current domain
            try{
                $PrimaryDC = ([Array](Get-NetDomainControllers))[0].Name
            }
            catch{
                $PrimaryDC = $Null
            }

            try {
                # reference - http://blogs.msdn.com/b/javaller/archive/2013/07/29/searching-across-active-directory-domains-in-powershell.aspx
                $dn = "DC=$($Domain.Replace('.', ',DC='))"

                # if we could grab the primary DC for the current domain, use that for the query
                if($PrimaryDC){
                    $CompSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$PrimaryDC/$dn")
                }
                else{
                    # otherwise try to connect to the DC for the target domain
                    $CompSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dn")
                }

                # create the searcher object with our specific filters
                if ($ServicePack -ne '*'){
                    $CompSearcher.filter="(&(objectClass=Computer)(dnshostname=$HostName)(operatingsystem=$OperatingSystem)(operatingsystemservicepack=$ServicePack)(servicePrincipalName=$SPN))"
                }
                else{
                    # server 2012 peculiarity- remove any mention to service pack
                    $CompSearcher.filter="(&(objectClass=Computer)(dnshostname=$HostName)(operatingsystem=$OperatingSystem)(servicePrincipalName=$SPN))"
                }

            }
            catch{
                Write-Warning "The specified domain $Domain does not exist, could not be contacted, or there isn't an existing trust."
            }
        }
        else{
            # otherwise, use the current domain
            if ($ServicePack -ne '*'){
                $CompSearcher = [adsisearcher]"(&(objectClass=Computer)(dnshostname=$HostName)(operatingsystem=$OperatingSystem)(operatingsystemservicepack=$ServicePack)(servicePrincipalName=$SPN))"
            }
            else{
                # server 2012 peculiarity- remove any mention to service pack
                $CompSearcher = [adsisearcher]"(&(objectClass=Computer)(dnshostname=$HostName)(operatingsystem=$OperatingSystem)(servicePrincipalName=$SPN))"
            }
        }

        if ($CompSearcher){

            # eliminate that pesky 1000 system limit
            $CompSearcher.PageSize = 200

            $CompSearcher.FindAll() | ? {$_} | ForEach-Object {
                $up = $true
                if($Ping){
                    $up = Test-Server -Server $_.properties.dnshostname
                }
                if($up){
                    # return full data objects
                    if ($FullData){
                        $properties = $_.Properties
                        $out = New-Object psobject

                        $properties.PropertyNames | % {
                            if ($_ -eq "objectsid"){
                                # convert the SID to a string
                                $out | Add-Member Noteproperty $_ ((New-Object System.Security.Principal.SecurityIdentifier($properties[$_][0],0)).Value)
                            }
                            elseif($_ -eq "objectguid"){
                                # convert the GUID to a string
                                $out | Add-Member Noteproperty $_ (New-Object Guid (,$properties[$_][0])).Guid
                            }
                            elseif( ($_ -eq "lastlogon") -or ($_ -eq "lastlogontimestamp") -or ($_ -eq "pwdlastset") ){
                                $out | Add-Member Noteproperty $_ ([datetime]::FromFileTime(($properties[$_][0])))
                            }
                            else {
                                $out | Add-Member Noteproperty $_ $properties[$_][0]
                            }
                        }
                        $out
                    }
                    else{
                        # otherwise we're just returning the DNS host name
                        $_.properties.dnshostname
                    }
                }
            }
        }

    }
}

function Get-NetGroup {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string]
        $GroupName = 'Domain Admins',

        [Switch]
        $FullData,

        [Switch]
        $Recurse,

        [string]
        $Domain,

        [string]
        $PrimaryDC
    )

    process {

        # if a domain is specified, try to grab that domain
        if ($Domain){

            # try to grab the primary DC for the current domain
            try{
                $PrimaryDC = ([Array](Get-NetDomainControllers))[0].Name
            }
            catch{
                $PrimaryDC = $Null
            }

            try {
                # reference - http://blogs.msdn.com/b/javaller/archive/2013/07/29/searching-across-active-directory-domains-in-powershell.aspx

                $dn = "DC=$($Domain.Replace('.', ',DC='))"

                # if we could grab the primary DC for the current domain, use that for the query
                if($PrimaryDC){
                    $GroupSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$PrimaryDC/$dn")
                }
                else{
                    # otherwise try to connect to the DC for the target domain
                    $GroupSearcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dn")
                }
                # samAccountType=805306368 indicates user objects
                $GroupSearcher.filter = "(&(objectClass=group)(name=$GroupName))"
            }
            catch{
                Write-Warning "The specified domain $Domain does not exist, could not be contacted, or there isn't an existing trust."
            }
        }
        else{
            $Domain = (Get-NetDomain).Name

            # otherwise, use the current domain
            $GroupSearcher = [adsisearcher]"(&(objectClass=group)(name=$GroupName))"
        }

        if ($GroupSearcher){
            $GroupSearcher.PageSize = 200
            $GroupSearcher.FindAll() | % {
                try{
                    $GroupFoundName = $_.properties.name[0]
                    $_.properties.member | ForEach-Object {
                        # for each user/member, do a quick adsi object grab
                        if ($PrimaryDC){
                            $properties = ([adsi]"LDAP://$PrimaryDC/$_").Properties
                        }
                        else {
                            $properties = ([adsi]"LDAP://$_").Properties
                        }

                        # check if the result is a user account- if not assume it's a group
                        if ($properties.samAccountType -ne "805306368"){
                            $isGroup = $True
                        }
                        else{
                            $isGroup = $False
                        }

                        $out = New-Object psobject
                        $out | add-member Noteproperty 'GroupDomain' $Domain
                        $out | Add-Member Noteproperty 'GroupName' $GroupFoundName

                        if ($FullData){
                            $properties.PropertyNames | % {
                                # TODO: errors on cross-domain users?
                                if ($_ -eq "objectsid"){
                                    # convert the SID to a string
                                    $out | Add-Member Noteproperty $_ ((New-Object System.Security.Principal.SecurityIdentifier($properties[$_][0],0)).Value)
                                }
                                elseif($_ -eq "objectguid"){
                                    # convert the GUID to a string
                                    $out | Add-Member Noteproperty $_ (New-Object Guid (,$properties[$_][0])).Guid
                                }
                                else {
                                    if ($properties[$_].count -eq 1) {
                                        $out | Add-Member Noteproperty $_ $properties[$_][0]
                                    }
                                    else {
                                        $out | Add-Member Noteproperty $_ $properties[$_]
                                    }
                                }
                            }
                        }
                        else {
                            $MemberDN = $properties.distinguishedName[0]
                            # extract the FQDN from the Distinguished Name
                            $MemberDomain = $MemberDN.subString($MemberDN.IndexOf("DC=")) -replace 'DC=','' -replace ',','.'

                            if ($properties.samAccountType -ne "805306368"){
                                $isGroup = $True
                            }
                            else{
                                $isGroup = $False
                            }

                            if ($properties.samAccountName){
                                # forest users have the samAccountName set
                                $MemberName = $properties.samAccountName[0]
                            }
                            else {
                                # external trust users have a SID, so convert it
                                try {
                                    $MemberName = Convert-SidToName $properties.cn[0]
                                }
                                catch {
                                    # if there's a problem contacting the domain to resolve the SID
                                    $MemberName = $properties.cn
                                }
                            }
                            $out | add-member Noteproperty 'MemberDomain' $MemberDomain
                            $out | add-member Noteproperty 'MemberName' $MemberName
                            $out | add-member Noteproperty 'IsGroup' $IsGroup
                            $out | add-member Noteproperty 'MemberDN' $MemberDN
                        }

                        $out

                        if($Recurse) {
                            # if we're recursiving and  the returned value isn't a user account, assume it's a group
                            if($IsGroup){
                                if($FullData){
                                    Get-NetGroup -Domain $Domain -PrimaryDC $PrimaryDC -FullData -Recurse -GroupName $properties.SamAccountName[0]
                                }
                                else {
                                    Get-NetGroup -Domain $Domain -PrimaryDC $PrimaryDC -Recurse -GroupName $properties.SamAccountName[0]
                                }
                            }
                        }
                    }
                }
                catch {
                    write-verbose $_
                }
            }
        }
    }
}


function Get-NetLocalGroup {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$True)]
        [string]
        $HostName = 'localhost',

        [string]
        $HostList,

        [string]
        $GroupName,

        [switch]
        $Recurse
    )

    process {

        $Servers = @()

        # if we have a host list passed, grab it
        if($HostList){
            if (Test-Path -Path $HostList){
                $Servers = Get-Content -Path $HostList
            }
            else{
                Write-Warning "[!] Input file '$HostList' doesn't exist!"
                $null
            }
        }
        else{
            # otherwise assume a single host name
            $Servers += Get-NameField $HostName
        }

        if (-not $GroupName){
            # resolve the SID for the local admin group - this should usually default to "Administrators"
            $objSID = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $objgroup = $objSID.Translate( [System.Security.Principal.NTAccount])
            $GroupName = ($objgroup.Value).Split('\')[1]
        }

        # query the specified group using the WINNT provider, and
        # extract fields as appropriate from the results
        foreach($Server in $Servers)
        {
            try{
                $members = @($([ADSI]"WinNT://$server/$groupname").psbase.Invoke('Members'))
                $members | ForEach-Object {
                    $out = New-Object psobject
                    $out | Add-Member Noteproperty 'Server' $Server

                    $AdsPath = ($_.GetType().InvokeMember('Adspath', 'GetProperty', $null, $_, $null)).Replace('WinNT://', '')

                    # try to translate the NT4 domain to a FQDN if possible
                    $name = Translate-NT4Name $AdsPath
                    if($name) {
                        $fqdn = $name.split("/")[0]
                        $objName = $AdsPath.split("/")[-1]
                        $name = "$fqdn/$objName"
                        $IsDomain = $True
                    }
                    else {
                        $name = $AdsPath
                        $IsDomain = $False
                    }

                    $out | Add-Member Noteproperty 'AccountName' $name

                    # translate the binary sid to a string
                    $out | Add-Member Noteproperty 'SID' ((New-Object System.Security.Principal.SecurityIdentifier($_.GetType().InvokeMember('ObjectSID', 'GetProperty', $null, $_, $null),0)).Value)

                    # if the account is local, check if it's disabled, if it's domain, always print $false
                    # TODO: fix this error?
                    $out | Add-Member Noteproperty 'Disabled' $( if(-not $IsDomain) { try { $_.GetType().InvokeMember('AccountDisabled', 'GetProperty', $null, $_, $null) } catch { 'ERROR' } } else { $False } )

                    # check if the member is a group
                    $IsGroup = ($_.GetType().InvokeMember('Class', 'GetProperty', $Null, $_, $Null) -eq 'group')
                    $out | Add-Member Noteproperty 'IsGroup' $IsGroup
                    $out | Add-Member Noteproperty 'IsDomain' $IsDomain
                    if($IsGroup){
                        $out | Add-Member Noteproperty 'LastLogin' ""
                    }
                    else{
                        try {
                            $out | Add-Member Noteproperty 'LastLogin' ( $_.GetType().InvokeMember('LastLogin', 'GetProperty', $null, $_, $null))
                        }
                        catch {
                            $out | Add-Member Noteproperty 'LastLogin' ""
                        }
                    }
                    $out

                    # if the result is a group domain object and we're recursing,
                    # try to resolve all the group member results
                    if($Recurse -and $IsDomain -and $IsGroup){
                        Write-Verbose "recurse!"
                        $FQDN = $name.split("/")[0]
                        $GroupName = $name.split("/")[1]
                        Get-NetGroup $GroupName -FullData -Recurse | % {
                            $out = New-Object psobject
                            $out | Add-Member Noteproperty 'Server' $name

                            $MemberDN = $_.distinguishedName
                            # extract the FQDN from the Distinguished Name
                            $MemberDomain = $MemberDN.subString($MemberDN.IndexOf("DC=")) -replace 'DC=','' -replace ',','.'

                            if ($_.samAccountType -ne "805306368"){
                                $MemberIsGroup = $True
                            }
                            else{
                                $MemberIsGroup = $False
                            }

                            if ($_.samAccountName){
                                # forest users have the samAccountName set
                                $MemberName = $_.samAccountName
                            }
                            else {
                                # external trust users have a SID, so convert it
                                try {
                                    $MemberName = Convert-SidToName $_.cn
                                }
                                catch {
                                    # if there's a problem contacting the domain to resolve the SID
                                    $MemberName = $_.cn
                                }
                            }

                            $out | Add-Member Noteproperty 'AccountName' "$MemberDomain/$MemberName"
                            $out | Add-Member Noteproperty 'SID' $_.objectsid
                            $out | Add-Member Noteproperty 'Disabled' $False
                            $out | Add-Member Noteproperty 'IsGroup' $MemberIsGroup
                            $out | Add-Member Noteproperty 'IsDomain' $True
                            $out | Add-Member Noteproperty 'LastLogin' ''
                            $out
                        }
                    }
                }
            }
            catch {
                Write-Warning "[!] Error: $_"
            }
        }
    }
}

function Get-NetSessions {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$True)]
        [string]
        $HostName = 'localhost',

        [string]
        $UserName = ''
    )

    begin {
        If ($PSBoundParameters['Debug']) {
            $DebugPreference = 'Continue'
        }
    }

    process {

        # process multiple object types
        $HostName = Get-NameField $HostName

        # arguments for NetSessionEnum
        $QueryLevel = 10
        $ptrInfo = [IntPtr]::Zero
        $EntriesRead = 0
        $TotalRead = 0
        $ResumeHandle = 0

        # get session information
        $Result = $Netapi32::NetSessionEnum($HostName, '', $UserName, $QueryLevel,[ref]$ptrInfo,-1,[ref]$EntriesRead,[ref]$TotalRead,[ref]$ResumeHandle)

        # Locate the offset of the initial intPtr
        $offset = $ptrInfo.ToInt64()

        Write-Debug "Get-NetSessions result: $Result"

        # 0 = success
        if (($Result -eq 0) -and ($offset -gt 0)) {

            # Work out how mutch to increment the pointer by finding out the size of the structure
            $Increment = $SESSION_INFO_10::GetSize()

            # parse all the result structures
            for ($i = 0; ($i -lt $EntriesRead); $i++){
                # create a new int ptr at the given offset and cast
                # the pointer as our result structure
                $newintptr = New-Object system.Intptr -ArgumentList $offset
                $Info = $newintptr -as $SESSION_INFO_10
                # return all the sections of the structure
                $Info | Select-Object *
                $offset = $newintptr.ToInt64()
                $offset += $increment

            }
            # free up the result buffer
            $Netapi32::NetApiBufferFree($PtrInfo) | Out-Null
        }
        else
        {
            switch ($Result) {
                (5)           {Write-Debug 'The user does not have access to the requested information.'}
                (124)         {Write-Debug 'The value specified for the level parameter is not valid.'}
                (87)          {Write-Debug 'The specified parameter is not valid.'}
                (234)         {Write-Debug 'More entries are available. Specify a large enough buffer to receive all entries.'}
                (8)           {Write-Debug 'Insufficient memory is available.'}
                (2312)        {Write-Debug 'A session does not exist with the computer name.'}
                (2351)        {Write-Debug 'The computer name is not valid.'}
                (2221)        {Write-Debug 'Username not found.'}
                (53)          {Write-Debug 'Hostname could not be found'}
            }
        }
    }
}

function Invoke-CheckLocalAdminAccess {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$True)]
        [string]
        $HostName = 'localhost'
    )

    begin {
        If ($PSBoundParameters['Debug']) {
            $DebugPreference = 'Continue'
        }
    }

    process {

        # process multiple object types
        $HostName = Get-NameField $HostName

        # 0xF003F - SC_MANAGER_ALL_ACCESS
        #   http://msdn.microsoft.com/en-us/library/windows/desktop/ms685981(v=vs.85).aspx
        $handle = $Advapi32::OpenSCManagerW("\\$HostName", 'ServicesActive', 0xF003F)

        Write-Debug "Invoke-CheckLocalAdminAccess handle: $handle"

        # if we get a non-zero handle back, everything was successful
        if ($handle -ne 0){
            # Close off the service handle
            $Advapi32::CloseServiceHandle($handle) | Out-Null
            $true
        }
        else{
            # otherwise it failed - get the last error
            $err = $Kernel32::GetLastError()
            # error codes - http://msdn.microsoft.com/en-us/library/windows/desktop/ms681382(v=vs.85).aspx
            Write-Debug "Invoke-CheckLocalAdminAccess LastError: $err"
            $false
        }
    }
}

function Get-NetFileServers {
    [CmdletBinding()]
    param(
        [string]
        $Domain
    )

    $Servers = @()

    Get-NetUser -Domain $Domain | % {
        if($_.homedirectory){
            $temp = $_.homedirectory.split("\\")[2]
            if($temp -and ($temp -ne '')){
                $Servers += $temp
            }
        }
        if($_.scriptpath){
            $temp = $_.scriptpath.split("\\")[2]
            if($temp -and ($temp -ne '')){
                $Servers += $temp
            }
        }
        if($_.profilepath){
            $temp = $_.profilepath.split("\\")[2]
            if($temp -and ($temp -ne '')){
                $Servers += $temp
            }
        }
    }

    # uniquify the fileserver list and return it
    $($Servers | Sort-Object -Unique)
}

function Invoke-StealthUserHunter {
    [CmdletBinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [String[]]
        $Hosts,

        [string]
        $HostList,

        [string]
        $GroupName = 'Domain Admins',

        [string]
        $TargetServerAdmins,

        [string]
        $OU,

        [string]
        $Filter,

        [string]
        $UserName,

        [Switch]
        $SPN,

        [Switch]
        $CheckAccess,

        [Switch]
        $StopOnSuccess,

        [Switch]
        $NoPing,

        [UInt32]
        $Delay = 0,

        [double]
        $Jitter = .3,

        [string]
        $UserList,

        [string]
        $Domain,

        [Switch]
        $ShowAll,

        [string]
        [ValidateSet("DC","File","All")]
        $Source ="All"
    )

    begin {
        if ($PSBoundParameters['Debug']) {
            $DebugPreference = 'Continue'
        }

        # users we're going to be searching for
        $TargetUsers = @()

        # resulting servers to query
        $Servers = @()

        # random object for delay
        $randNo = New-Object System.Random

        # get the current user
        $CurrentUser = Get-NetCurrentUser
        $CurrentUserBase = ([Environment]::UserName)

        # get the target domain
        if($Domain){
            $targetDomain = $Domain
        }
        else{
            # use the local domain
            $targetDomain = $null
        }

        Write-Verbose "[*] Running Invoke-StealthUserHunter with delay of $Delay"
        if($targetDomain){
            Write-Verbose "[*] Domain: $targetDomain"
        }

        # if we're showing all results, skip username enumeration
        if($ShowAll){}
        # if we want to hunt for the effective domain users who can access a target server
        elseif($TargetServerAdmins){
            $TargetUsers = Get-NetLocalGroup WINDOWS4.dev.testlab.local -Recurse | ?{(-not $_.IsGroup) -and $_.IsDomain} | %{ ($_.AccountName).split("/")[1].toLower() }
        }
        # if we get a specific username, only use that
        elseif ($UserName){
            Write-Verbose "[*] Using target user '$UserName'..."
            $TargetUsers += $UserName.ToLower()
        }
        # get the users from a particular OU if one is specified
        elseif($OU){
            $TargetUsers = Get-NetUser -OU $OU | ForEach-Object {$_.samaccountname}
        }
        # use a specific LDAP query string to query for users
        elseif($Filter){
            $TargetUsers = Get-NetUser -Filter $Filter | ForEach-Object {$_.samaccountname}
        }
        # read in a target user list if we have one
        elseif($UserList){
            $TargetUsers = @()
            # make sure the list exists
            if (Test-Path -Path $UserList){
                $TargetUsers = Get-Content -Path $UserList
            }
            else {
                Write-Warning "[!] Input file '$UserList' doesn't exist!"
                return
            }
        }
        else{
            # otherwise default to the group name to query for target users
            Write-Verbose "[*] Querying domain group '$GroupName' for target users..."
            $temp = Get-NetGroup -GroupName $GroupName -Domain $targetDomain | % {$_.MemberName}
            # lower case all of the found usernames
            $TargetUsers = $temp | ForEach-Object {$_.ToLower() }
        }

        if ((-not $ShowAll) -and (($TargetUsers -eq $null) -or ($TargetUsers.Count -eq 0))){
            Write-Warning "[!] No users found to search for!"
            return $Null
        }

        # if we're using a host list, read the targets in and add them to the target list
        if($HostList){
            if (Test-Path -Path $HostList){
                $Hosts = Get-Content -Path $HostList
            }
            else{
                Write-Warning "[!] Input file '$HostList' doesn't exist!"
                return
            }
        }
        elseif($HostFilter){
            Write-Verbose "[*] Querying domain $targetDomain for hosts with filter '$HostFilter'"
            $Hosts = Get-NetComputers -Domain $targetDomain -HostName $HostFilter
        }
        elseif($SPN){
            # set the unique set of SPNs from user objects
            $Hosts = Get-NetUserSPNs | Foreach-Object {
                $_.ServicePrincipalName | Foreach-Object {
                    ($_.split("/")[1]).split(":")[0]
                }
            } | Sort-Object -Unique
        }
    }

    process {

        if ( (-not ($Hosts)) -or ($Hosts.length -eq 0)) {

            if ($Source -eq "File"){
                Write-Verbose "[*] Querying domain $targetDomain for File Servers..."
                [Array]$Hosts = Get-NetFileServers -Domain $targetDomain

            }
            elseif ($Source -eq "DC"){
                Write-Verbose "[*] Querying domain $targetDomain for Domain Controllers..."
                [Array]$Hosts = Get-NetDomainControllers -Domain $targetDomain | % {$_.Name}
            }
            elseif ($Source -eq "All") {
                Write-Verbose "[*] Querying domain $targetDomain for hosts..."
                [Array]$Hosts  = Get-NetFileServers -Domain $targetDomain
                $Hosts += Get-NetDomainControllers -Domain $targetDomain | % {$_.Name}
            }
        }

        # uniquify the host list and then randomize it
        $Hosts = $Hosts | Sort-Object -Unique
        $Hosts = Get-ShuffledArray $Hosts
        $HostCount = $Hosts.Count
        Write-Verbose "[*] Total number of hosts: $HostCount"

        $counter = 0

        # iterate through each target file server
        foreach ($server in $Hosts){

            $found = $false
            $counter = $counter + 1

            Write-Verbose "[*] Enumerating host $server ($counter of $($Hosts.count))"

            # sleep for our semi-randomized interval
            Start-Sleep -Seconds $randNo.Next((1-$Jitter)*$Delay, (1+$Jitter)*$Delay)

            # optionally check if the server is up first
            $up = $true
            if(-not $NoPing){
                $up = Test-Server -Server $server
            }
            if ($up){
                # grab all the sessions for this fileserver
                $sessions = Get-NetSessions $server

                # search through all the sessions for a target user
                foreach ($session in $sessions) {
                    Write-Debug "[*] Session: $session"
                    # extract fields we care about
                    $username = $session.sesi10_username
                    $cname = $session.sesi10_cname
                    $activetime = $session.sesi10_time
                    $idletime = $session.sesi10_idle_time

                    # make sure we have a result
                    if (($username -ne $null) -and ($username.trim() -ne '') -and ($username.trim().toLower() -ne $CurrentUserBase)){
                        # if the session user is in the target list, display some output
                        if ($ShowAll -or $($TargetUsers -contains $username)){
                            $found = $true
                            $ip = Get-HostIP -hostname $Server

                            if($cname.StartsWith("\\")){
                                $cname = $cname.TrimStart("\")
                            }

                            $out = new-object psobject
                            $out | add-member Noteproperty 'TargetUser' $username
                            $out | add-member Noteproperty 'Computer' $server
                            $out | add-member Noteproperty 'IP' $ip
                            $out | add-member Noteproperty 'SessionFrom' $cname

                            # see if we're checking to see if we have local admin access on this machine
                            if ($CheckAccess){
                                $admin = Invoke-CheckLocalAdminAccess -Hostname $cname
                                $out | add-member Noteproperty 'LocalAdmin' $admin
                            }
                            else{
                                $out | add-member Noteproperty 'LocalAdmin' $Null
                            }
                            $out
                        }
                    }
                }
            }

            if ($StopOnSuccess -and $found) {
                Write-Verbose "[*] Returning early"
                return
           }
        }
    }
}

function Get-NetDomainTrusts {
    [CmdletBinding()]
    param(
        [string]
        $Domain
    )

    $d = Get-NetDomain -Domain $Domain
    if($d){
        $d.GetAllTrustRelationships()
    }
}

function Get-NetForestTrusts {
    [CmdletBinding()]
    param(
        [string]
        $Forest
    )

    $f = (Get-NetForest -Forest $Forest)
    if($f){
        $f.GetAllTrustRelationships()
    }
}

function Get-DomainInfo {
    "`n[+] Get-NetDomain"
    Get-NetDomain
    "[+] Invoke-StealthUserHunter`n"
    Invoke-StealthUserHunter
    "[+] Get-NetComputers`n"
    Get-NetComputers
    "`n[+] Get-NetForest`n"
    Get-NetForest
    "[+] Get-NetForestDomains`n"
    Get-NetForestDomains
    "[+] Get-NetDomainControllers`n"
    Get-NetDomainControllers
    "[+] Get-NetDomainTrusts`n"
    Get-NetDomainTrusts
    "[+] Get-NetForestTrusts`n"
    Get-NetForestTrusts

    #If Get-NetCurrentUser returns the username appended to the domain
    $userName = Get-NetCurrentUser
    if ($userName.contains("\")){$userName = $userName.split('\')[1]}

    "[+] Get-NetUser (Only for current user)`n"
    Get-NetUser $userName
    "[+] Get-NetLocalGroup`n"
    Get-NetLocalGroup

}


# expose the Win32API functions and datastructures below
# using PSReflect

$Mod = New-InMemoryModule -ModuleName Win32

# all of the Win32 API functions we need
$FunctionDefinitions = @(
    (func netapi32 NetShareEnum ([Int]) @([string], [Int], [IntPtr].MakeByRefType(), [Int], [Int32].MakeByRefType(), [Int32].MakeByRefType(), [Int32].MakeByRefType())),
    (func netapi32 NetWkstaUserEnum ([Int]) @([string], [Int], [IntPtr].MakeByRefType(), [Int], [Int32].MakeByRefType(), [Int32].MakeByRefType(), [Int32].MakeByRefType())),
    (func netapi32 NetSessionEnum ([Int]) @([string], [string], [string], [Int], [IntPtr].MakeByRefType(), [Int], [Int32].MakeByRefType(), [Int32].MakeByRefType(), [Int32].MakeByRefType())),
    (func netapi32 NetFileEnum ([Int]) @([string], [string], [string], [Int], [IntPtr].MakeByRefType(), [Int], [Int32].MakeByRefType(), [Int32].MakeByRefType(), [Int32].MakeByRefType())),
    (func netapi32 NetConnectionEnum ([Int]) @([string], [string], [Int], [IntPtr].MakeByRefType(), [Int], [Int32].MakeByRefType(), [Int32].MakeByRefType(), [Int32].MakeByRefType())),
    (func netapi32 NetApiBufferFree ([Int]) @([IntPtr])),
    (func advapi32 OpenSCManagerW ([IntPtr]) @([string], [string], [Int])),
    (func advapi32 CloseServiceHandle ([Int]) @([IntPtr])),
    
    (func wtsapi32 WTSOpenServerEx ([IntPtr]) @([string])),
    (func wtsapi32 WTSEnumerateSessionsEx ([Int]) @([IntPtr], [Int32].MakeByRefType(), [Int], [IntPtr].MakeByRefType(),  [Int32].MakeByRefType())),
    (func wtsapi32 WTSQuerySessionInformation ([Int]) @([IntPtr], [Int], [Int], [IntPtr].MakeByRefType(), [Int32].MakeByRefType())),
    (func wtsapi32 WTSFreeMemoryEx ([Int]) @([Int32], [IntPtr], [Int32])),
    (func wtsapi32 WTSFreeMemory ([Int]) @([IntPtr])),
    (func wtsapi32 WTSCloseServer ([Int]) @([IntPtr])),
    (func kernel32 GetLastError ([Int]) @())
)

$WTSConnectState = psenum $Mod WTS_CONNECTSTATE_CLASS UInt16 @{
    Active       =    0
    Connected    =    1
    ConnectQuery =    2
    Shadow       =    3
    Disconnected =    4
    Idle         =    5
    Listen       =    6
    Reset        =    7
    Down         =    8
    Init         =    9
}

# the WTSEnumerateSessionsEx result structure
$WTS_SESSION_INFO_1 = struct $Mod WTS_SESSION_INFO_1 @{
    ExecEnvId = field 0 UInt32
    State = field 1 $WTSConnectState
    SessionId = field 2 UInt32
    pSessionName = field 3 String -MarshalAs @('LPWStr')
    pHostName = field 4 String -MarshalAs @('LPWStr')
    pUserName = field 5 String -MarshalAs @('LPWStr')
    pDomainName = field 6 String -MarshalAs @('LPWStr')
    pFarmName = field 7 String -MarshalAs @('LPWStr')
}

# the particular WTSQuerySessionInformation result structure
$WTS_CLIENT_ADDRESS = struct $mod WTS_CLIENT_ADDRESS @{
    AddressFamily = field 0 UInt32
    Address = field 1 Byte[] -MarshalAs @('ByValArray', 20)
}

# the NetShareEnum result structure
$SHARE_INFO_1 = struct $Mod SHARE_INFO_1 @{
    shi1_netname = field 0 String -MarshalAs @('LPWStr')
    shi1_type = field 1 UInt32
    shi1_remark = field 2 String -MarshalAs @('LPWStr')
}

# the NetWkstaUserEnum result structure
$WKSTA_USER_INFO_1 = struct $Mod WKSTA_USER_INFO_1 @{
    wkui1_username = field 0 String -MarshalAs @('LPWStr')
    wkui1_logon_domain = field 1 String -MarshalAs @('LPWStr')
    wkui1_oth_domains = field 2 String -MarshalAs @('LPWStr')
    wkui1_logon_server = field 3 String -MarshalAs @('LPWStr')
}

# the NetSessionEnum result structure
$SESSION_INFO_10 = struct $Mod SESSION_INFO_10 @{
    sesi10_cname = field 0 String -MarshalAs @('LPWStr')
    sesi10_username = field 1 String -MarshalAs @('LPWStr')
    sesi10_time = field 2 UInt32
    sesi10_idle_time = field 3 UInt32
}

# the NetFileEnum result structure
$FILE_INFO_3 = struct $Mod FILE_INFO_3 @{
    fi3_id = field 0 UInt32
    fi3_permissions = field 1 UInt32
    fi3_num_locks = field 2 UInt32
    fi3_pathname = field 3 String -MarshalAs @('LPWStr')
    fi3_username = field 4 String -MarshalAs @('LPWStr')
}

# the NetConnectionEnum result structure
$CONNECTION_INFO_1 = struct $Mod CONNECTION_INFO_1 @{
    coni1_id = field 0 UInt32
    coni1_type = field 1 UInt32
    coni1_num_opens = field 2 UInt32
    coni1_num_users = field 3 UInt32
    coni1_time = field 4 UInt32
    coni1_username = field 5 String -MarshalAs @('LPWStr')
    coni1_netname = field 6 String -MarshalAs @('LPWStr')
}

$Types = $FunctionDefinitions | Add-Win32Type -Module $Mod -Namespace 'Win32'
$Netapi32 = $Types['netapi32']
$Advapi32 = $Types['advapi32']
$Kernel32 = $Types['kernel32']
$Wtsapi32 = $Types['wtsapi32']
