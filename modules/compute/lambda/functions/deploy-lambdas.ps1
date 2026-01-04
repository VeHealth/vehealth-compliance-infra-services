# ==============================================================================
# Deploy Driver Document Lambda Functions
# ==============================================================================
# Builds and deploys document-upload, document-review, and document-expiry
# Lambda functions to AWS
# ==============================================================================

param(
    [string]$Environment = "dev",
    [string]$Region = "us-east-2"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying Document Lambda Functions" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$functions = @("document-upload", "document-review", "document-expiry")

foreach ($func in $functions) {
    Write-Host "`nProcessing $func..." -ForegroundColor Yellow

    $funcDir = Join-Path $PSScriptRoot $func

    if (!(Test-Path $funcDir)) {
        Write-Host "Error: Directory not found: $funcDir" -ForegroundColor Red
        exit 1
    }

    # Navigate to function directory
    Push-Location $funcDir

    try {
        # Install dependencies
        Write-Host "  Installing dependencies..." -ForegroundColor Gray
        npm install --production --silent

        # Create deployment package
        Write-Host "  Creating deployment package..." -ForegroundColor Gray
        $zipFile = "$func.zip"

        if (Test-Path $zipFile) {
            Remove-Item $zipFile -Force
        }

        # Create zip with all files
        Compress-Archive -Path .\* -DestinationPath $zipFile -Force

        # Get file size
        $zipSize = (Get-Item $zipFile).Length / 1MB
        Write-Host "  Package size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Gray

        # Update Lambda function code
        $functionName = "vehealth-$Environment-$func"
        Write-Host "  Deploying to Lambda: $functionName..." -ForegroundColor Gray

        aws lambda update-function-code `
            --function-name $functionName `
            --zip-file fileb://$zipFile `
            --region $Region `
            --output json | ConvertFrom-Json | Select-Object FunctionName, LastModified, CodeSize, Runtime | Format-List

        # Update environment variables with RDS_SECRET_ARN and DATABASE_NAME
        Write-Host "  Updating environment variables..." -ForegroundColor Gray
        $secretArn = "arn:aws:secretsmanager:${Region}:274106733152:secret:vehealth/${Environment}/rds/master-PAVje8"

        aws lambda update-function-configuration `
            --function-name $functionName `
            --environment "Variables={ENVIRONMENT=$Environment,LOG_LEVEL=DEBUG,RDS_PROXY_ENDPOINT=vehealth-$Environment-postgresql.cl28u6uogxmf.$Region.rds.amazonaws.com,RDS_SECRET_ARN=$secretArn,DATABASE_NAME=vehealth,DOCUMENTS_BUCKET=vehealth-$Environment-driver-documents}" `
            --region $Region `
            --output json | Out-Null

        Write-Host "  ✓ $func deployed successfully" -ForegroundColor Green

    } catch {
        Write-Host "  ✗ Error deploying $func : $_" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Pop-Location
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "All Lambda functions deployed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Test document upload API endpoint" -ForegroundColor White
Write-Host "2. Test document list API endpoint" -ForegroundColor White
Write-Host "3. Test document review API endpoint" -ForegroundColor White
