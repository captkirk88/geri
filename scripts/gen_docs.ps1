if (-not (Test-Path docs)) {
    New-Item -ItemType Directory -Path docs | Out-Null
}

Write-Host "=> Generating documentation..."
odin doc . -all-packages -doc-format -out:docs/odin.odin-doc

Write-Host "=> Documentation generated successfully in docs/odin.odin-doc"
