## Cleanup Script (Cleanup-A  ppRegistration-Cosmos.ps1)

### Purpose
The cleanup script safely removes all resources created by the setup script to prevent unnecessary Azure costs and cleanup the environment.

### Parameters
- `ConfigPath` (Optional, Default: "azure-config.json"): Path to the configuration file created during setup

### Usage
```powershell
.\Cleanup-AppRegistration-Cosmos.ps1
```

### Cleanup Process
1. Removes all role assignments
2. Deletes the service principal
3. Removes the app registration
4. Optionally removes the Cosmos DB account (with confirmation prompt)
5. Cleans up local configuration files

### Output Files
- `cleanup_log.txt`: Detailed cleanup process log

## Logging
Both scripts implement comprehensive logging with:
- Timestamp for each operation
- Color-coded output based on message type:
  - Info: Gray
  - Warning: Yellow
  - Error: Red
  - Success: Green
- All operations logged to respective log files

## Error Handling
- Both scripts include try/catch blocks for proper error handling
- Detailed error messages and stack traces are logged
- Clean rollback of operations when possible

## Security Notes
- Client secrets are generated with 1-year expiration
- All sensitive information is logged and saved to local files
- Environment variables are generated for secure configuration
- Role assignments follow least-privilege principle

## Best Practices
1. Review the log files after running either script
2. Backup any important data before running the cleanup script
3. Store the generated client secret securely
4. Update the `.env.local` file in your application
5. Rotate client secrets periodically

## Troubleshooting
Common issues and solutions:

1. Permission Errors:
   - Ensure you have sufficient Azure AD and subscription permissions
   - Verify you're signed in with the correct account

2. Resource Name Conflicts:
   - Check if resources with the same names exist
   - Use unique names for Cosmos DB account

3. Module Installation Issues:
   - Run PowerShell as administrator
   - Clear PowerShell module cache if needed

## Support
For issues or questions:
1. Check the log files for detailed error messages
2. Verify Azure subscription permissions
3. Ensure all prerequisites are installed
4. Contact Azure support for platform-specific issues

## Contributing
When modifying these scripts:
1. Maintain the logging structure
2. Update documentation as needed
3. Test thoroughly in a non-production environment
4. Follow PowerShell best practices