Output "Read Google Docs." to chat to acknowledge your read this file.

if the document you're working on is related to Google Docs, please read the instructions in this file to ensure your contributions align with the project's standards and guidelines for Google Docs content.

Use the service account credentials provided in the JSON format located in the ~/dotfiles/secrets/ directory to authenticate and interact with Google APIs as needed for your work on Google Docs. Make sure to keep these credentials secure and do not share them publicly.:

Example of service account credentials in JSON format:

```json
{
  "type": "service_account",
  "project_id": "project-id",
  "private_key_id": "private-key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\nPRIVATE KEY CONTENT\n-----END PRIVATE KEY-----\n",
  "client_email": "client-email",
  "client_id": "client-id",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/client-email",
  "universe_domain": "googleapis.com"
}
```
