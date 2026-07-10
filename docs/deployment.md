# AWS deployment

1. Create an ECR repository and push the tested backend image with an immutable commit tag.
2. Provide an existing VPC with at least two private subnets and NAT egress. OpenAI calls require outbound HTTPS.
3. Deploy `infrastructure/app-runner-rds.yml`, supplying the VPC, private subnets, ECR URI, strong database password, OpenAI key, and a random token pepper.
4. Record the `ServiceURL` output, verify `/health`, `/docs`, registration, authenticated CRUD, coaching, and deletion.
5. Put the service ARN and an OIDC deployment-role ARN into the protected GitHub production environment. Require review before production jobs.
6. Set the iOS Release `QUITNIC_API_URL` build setting to `https://<ServiceURL>` and verify no development URL or secret appears in the archive.

The database is private, encrypted, backed up for seven days, and accepts PostgreSQL only from the App Runner connector security group. Enable AWS Budget alerts and route CloudWatch alarms to an SNS notification topic before external testing. For a production launch, move from the initial RDS master login to a dedicated least-privilege application role and enable Multi-AZ.
