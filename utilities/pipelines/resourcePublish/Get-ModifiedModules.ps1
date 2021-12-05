function Get-ModifiedFiles {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string] $Commit = 'HEAD^',

        [Parameter(Position = 1)]
        [string] $CompareCommit = 'HEAD'
    )
    $Diff = git diff --name-only --diff-filter=AM $Commit $CompareCommit
    $ModifiedFiles = $Diff | Get-Item
    Write-Verbose 'The following files have been updated:'
    $ModifiedFiles | ForEach-Object {
        Write-Verbose "   $($_.FullName)"
    }
    return $ModifiedFiles
}

function Get-ModifiedModuleFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $ModuleFolderPath
    )
    Write-Verbose "Looking for changed modules under : '$ModuleFolderPath'"
    $ModifiedModuleFiles = Get-ModifiedFiles | Where-Object { $_.FullName -like "$ModuleFolderPath*deploy.bicep" }

    if ($ModifiedModuleFiles.Count -eq 0) {
        throw 'No Modified module files found.'
    }

    Write-Verbose 'The following modules have been updated:'
    $ModifiedModuleFiles | ForEach-Object {
        Write-Verbose "   $($_.FullName)"
    }
    return $ModifiedModuleFiles
}

function Get-ModuleName {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $ModuleFilePath
    )
    $FolderPath = Split-Path -Path $ModuleFilePath -Parent
    $ModuleName = $FolderPath.Replace('/', '\').Split('\arm\')[-1].Replace('\', '.').ToLower()
    return $ModuleName
}

function Get-ParentModule {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $ModuleFilePath,

        [Parameter()]
        [switch] $Recurse

    )

    $ModuleFolderPath = Split-Path $ModuleFilePath -Parent
    $ParentFolderPath = Split-Path $ModuleFolderPath -Parent
    $ParentDeployFilePath = Join-Path $ParentFolderPath 'deploy.bicep'
    if (-not (Test-Path -Path $ParentDeployFilePath)) {
        Write-Verbose "No parent deploy file found at: $ParentDeployFilePath"
        return
    }
    Write-Verbose "Parent deploy file found at: $ParentDeployFilePath"
    $ParentModuleFiles = New-Object -TypeName System.Collections.ArrayList
    $ParentModuleFiles += $ParentDeployFilePath | Get-Item
    if ($Recurse) {
        $ParentModuleFiles += Get-ParentModule $ParentDeployFilePath -Recurse
    }
    return $ParentModuleFiles
}

function Get-GitDistance {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string] $Commit = 'HEAD^',

        [Parameter(Position = 1)]
        [string] $CompareCommit = 'HEAD'
    )
    $Distance = (git rev-list $Commit $CompareCommit).count - 1
    return $Distance
}

function Get-ModuleVersion {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $ModuleFilePath
    )
    $ModuleFile = Get-Item -Path $ModuleFilePath
    $ModuleFolder = Split-Path -Path $ModuleFile -Parent
    $VersionFilePath = Join-Path $ModuleFolder 'version.json'

    if (-not (Test-Path -Path $VersionFilePath)) {
        throw "No version file found at: $VersionFilePath"
    }

    $VersionFileContent = Get-Content $VersionFilePath | ConvertFrom-Json
    $Version = $VersionFileContent.version

    return $Version
}

function Get-NewModuleVersion {
    [CmdletBinding()]
    param (
        $ModuleFilePath
    )
    $Version = Get-ModuleVersion -ModuleFilePath $ModuleFilePath
    $Patch = Get-GitDistance
    $NewVersion = [System.Version]"$Version.$Patch"
    return $NewVersion.ToString()
}

function Get-ModifiedModules {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $ModuleFilePath = 'C:\Users\marst\OneDrive - Microsoft\Code\Azure\ResourceModules\arm\Microsoft.Storage\storageAccounts\deploy.bicep'
    )

    $ModuleFolderPath = Split-Path $ModuleFilePath -Parent

    Write-Output "Checking for modified module files under: '$ModuleFolderPath'"
    $ModifiedModuleFiles = Get-ModifiedModuleFiles -ModuleFolderPath $ModuleFolderPath
    Write-Output "Modified module files: $($ModifiedModuleFiles.Count)"

    $ModulesToUpdate = New-Object -TypeName System.Collections.ArrayList
    $ModifiedModuleFiles | Sort-Object FullName -Descending | ForEach-Object {
        $ModuleName = Get-ModuleName -ModuleFilePath $_.FullName
        $ModuleVersion = Get-NewModuleVersion -ModuleFilePath $_.FullName
        $ModulesToUpdate += [pscustomobject]@{
            Name    = $ModuleName
            Version = $ModuleVersion
            ModulePath = $_.FullName
        }
        Write-Output "Update: $ModuleName - $ModuleVersion"

        Write-Output 'Checking for parent modules'
        $ParentModuleFiles = Get-ParentModule -ModuleFilePath $_ -Recurse
        Write-Output "Checking for parent modules - Found $($ParentModuleFiles.Count)"
        $ParentModuleFiles
        $ParentModuleFiles | ForEach-Object {
            $ParentModuleName = Get-ModuleName -ModuleFilePath $_.FullName
            $ParentModuleVersion = Get-NewModuleVersion -ModuleFilePath $_.FullName

            $ModulesToUpdate += [pscustomobject]@{
                Name       = $ParentModuleName
                Version    = $ParentModuleVersion
                ModulePath = $_.FullName
            }
            Write-Output "Update parent: $ParentModuleName - $ParentModuleVersion"
        }
    }

    $ModulesToUpdate = $ModulesToUpdate | Sort-Object Name -Descending -Unique

    return $ModulesToUpdate
}
