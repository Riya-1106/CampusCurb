# Render Deployment & Environment Configuration Guide

## Email Setup (Required for College Signups)

To enable email notifications for college signup approvals and rejections, you need to configure SMTP settings on Render:

### Using Gmail:

1. **Enable 2-Factor Authentication** on your Gmail account
2. **Generate an App Password**:
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" and "Windows Computer" (or your device)
   - Google will generate a 16-character password
   
3. **On Render Dashboard**, add these environment variables to your service:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USERNAME=your-email@gmail.com
   SMTP_PASSWORD=<the-16-char-password-from-step-2>
   SMTP_FROM_EMAIL=your-email@gmail.com
   SMTP_FROM_NAME=CampusCurb
   SMTP_USE_TLS=true
   SMTP_USE_SSL=false
   ```

### Using Other Email Providers:

Adjust SMTP_HOST and SMTP_PORT according to your provider:
- **Outlook**: smtp.outlook.com:587
- **SendGrid**: smtp.sendgrid.net:587
- **Mailgun**: smtp.mailgun.org:587

## Firebase Configuration

Your Firebase credentials should already be set up. Verify these variables are in Render:
- FIREBASE_PROJECT_ID
- FIREBASE_PRIVATE_KEY
- FIREBASE_CLIENT_EMAIL

## Troubleshooting

### Email not sending on Render?
1. Check application logs on Render dashboard: `Logs` tab
2. Look for "SMTP is not configured" error - ensure all variables are set correctly
3. Verify your email provider allows third-party app connections
4. For Gmail: Make sure you created an "App Password" not using your regular Gmail password

### Check SMTP Connection:
In Render logs, you should see:
- ✅ "Password setup email sent successfully" for approvals
- ✅ "Rejection email sent" for rejections
- ❌ "Failed to send email: ..." indicates configuration issue

## Local Development

For local testing, create a `.env` file in the `backend` directory with the same variables. The app will read them automatically.
