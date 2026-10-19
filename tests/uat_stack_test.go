package test

// TestUatStackOnFloci builds the whole UAT environment on Floci, in the same
// order and with the same values as scripts/tf.sh:
//
//   bootstrap -> account -> uat/network -> uat/data -> uat/platform -> uat/apps
//
// After each layer it checks, through the AWS API, the promises the plan
// makes: the database is private and encrypted, db-sg only accepts app-sg,
// data subnets have no internet route, every task above the first runs on
// Spot, every hive-* role carries the permission boundary, and so on.
//
// Known Floci gaps (the code is right; the emulator is not):
//   - Access Analyzer GetAnalyzer and ECR PutRegistryScanningConfiguration are
//     not implemented, so enable_access_analyzer and enable_inspector_ecr are
//     switched off for the local run only.
//   - Floci does not remove AWS's default allow-all egress rule when the
//     provider revokes it (it compares ports on a protocol -1 rule). That one
//     unlabelled rule is ignored; any other egress fails the test.
//   - Floci's ECS reconciler cannot start tasks for services that use a
//     capacity-provider strategy, so running containers are not tested here.

import (
	"context"
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/applicationautoscaling"
	aastypes "github.com/aws/aws-sdk-go-v2/service/applicationautoscaling/types"
	"github.com/aws/aws-sdk-go-v2/service/budgets"
	"github.com/aws/aws-sdk-go-v2/service/cloudtrail"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/configservice"
	cfgtypes "github.com/aws/aws-sdk-go-v2/service/configservice/types"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ecr"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	ecstypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	elb "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	"github.com/aws/aws-sdk-go-v2/service/guardduty"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	"github.com/aws/aws-sdk-go-v2/service/route53"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	smtypes "github.com/aws/aws-sdk-go-v2/service/secretsmanager/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/wafv2"
	waftypes "github.com/aws/aws-sdk-go-v2/service/wafv2/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var ctx = context.Background()

func TestUatStackOnFloci(t *testing.T) {
	requireFloci(t)
	cfg := awsConfig(t)

	repo := copyRepo(t)
	prepareCopy(t, repo)
	switchOffFlociGaps(t, repo)
	ensureHostedZone(t, cfg)

	apply := func(target string) {
		t.Logf("==> applying %s", target)
		terraform.InitAndApply(t, stackOptions(t, repo, target))
	}

	if !t.Run("bootstrap", func(t *testing.T) {
		apply("bootstrap")
		checkBootstrap(t, cfg, repo)
	}) {
		t.FailNow()
	}
	if !t.Run("account", func(t *testing.T) {
		apply("account")
		checkAccount(t, cfg)
	}) {
		t.FailNow()
	}

	var net networkIDs
	if !t.Run("network", func(t *testing.T) {
		apply(env + "/network")
		net = checkNetwork(t, cfg)
	}) {
		t.FailNow()
	}
	if !t.Run("data", func(t *testing.T) {
		apply(env + "/data")
		checkData(t, cfg, net)
	}) {
		t.FailNow()
	}
	if !t.Run("platform", func(t *testing.T) {
		apply(env + "/platform")
		checkPlatform(t, cfg)
	}) {
		t.FailNow()
	}
	t.Run("apps", func(t *testing.T) {
		apply(env + "/apps")
		checkApps(t, cfg, net)
	})
}

// --- setup -----------------------------------------------------------------

func switchOffFlociGaps(t *testing.T, repo string) {
	t.Helper()
	p := filepath.Join(repo, "envs", "account.tfvars")
	b, err := os.ReadFile(p)
	require.NoError(t, err)
	s := strings.Replace(string(b), "enable_access_analyzer = true", "enable_access_analyzer = false", 1)
	s = strings.Replace(s, "enable_inspector_ecr   = true", "enable_inspector_ecr   = false", 1)
	require.NoError(t, os.WriteFile(p, []byte(s), 0o644))
}

// The platform layer looks up the existing public zone, as it does in the real account.
func ensureHostedZone(t *testing.T, cfg aws.Config) {
	t.Helper()
	r := route53.NewFromConfig(cfg)
	out, err := r.ListHostedZonesByName(ctx, &route53.ListHostedZonesByNameInput{DNSName: aws.String(zoneName)})
	require.NoError(t, err)
	for _, z := range out.HostedZones {
		if strings.TrimSuffix(aws.ToString(z.Name), ".") == zoneName {
			return
		}
	}
	_, err = r.CreateHostedZone(ctx, &route53.CreateHostedZoneInput{
		Name:            aws.String(zoneName),
		CallerReference: aws.String("hive-terratest"),
	})
	require.NoError(t, err)
}

// --- bootstrap -------------------------------------------------------------

func checkBootstrap(t *testing.T, cfg aws.Config, repo string) {
	backend, err := os.ReadFile(filepath.Join(repo, "envs", "backend.hcl"))
	require.NoError(t, err, "bootstrap must write envs/backend.hcl")
	assert.Contains(t, string(backend), `bucket       = "hive-tfstate-`+flociAccount+`"`)
	assert.Contains(t, string(backend), "use_lockfile = true")

	bucket := "hive-tfstate-" + flociAccount
	checkPrivateBucket(t, cfg, bucket, "aws:kms")
	pol := bucketPolicy(t, cfg, bucket)
	assert.Contains(t, pol, "OnlyHiveAdminAndBreakGlass", "state bucket must be limited to hive-admin and break-glass")
	assert.Contains(t, pol, "role/hive-admin")
}

// --- account ---------------------------------------------------------------

func checkAccount(t *testing.T, cfg aws.Config) {
	c := iam.NewFromConfig(cfg)
	boundaryArn := "arn:aws:iam::" + flociAccount + ":policy/hive-boundary"

	doc := policyDocument(t, c, boundaryArn)
	for _, sid := range []string{
		"ProtectTheRunningStack", "NoIamUsersOrAccessKeys", "IamOnlyForHiveRolesAndPolicies",
		"PassOnlyHiveRoles", "NewRolesMustCarryThisBoundary", "NobodyRemovesABoundary",
		"GuardrailsAreReadOnly", "NoAccountWideSwitches",
	} {
		assert.Contains(t, doc, `"`+sid+`"`, "permission boundary is missing %s", sid)
	}
	assert.Contains(t, doc, "s3:PutAccountPublicAccessBlock", "boundary must block account-wide S3 Block Public Access changes")

	role, err := c.GetRole(ctx, &iam.GetRoleInput{RoleName: aws.String("hive-admin")})
	require.NoError(t, err)
	require.NotNil(t, role.Role.PermissionsBoundary, "hive-admin must carry the boundary")
	assert.Equal(t, boundaryArn, aws.ToString(role.Role.PermissionsBoundary.PermissionsBoundaryArn))
	assert.EqualValues(t, 3600, aws.ToInt32(role.Role.MaxSessionDuration), "sessions last one hour")
	trust, _ := url.QueryUnescape(aws.ToString(role.Role.AssumeRolePolicyDocument))
	assert.Contains(t, trust, "aws:MultiFactorAuthPresent", "hive-admin may only be assumed with MFA")

	gd, err := guardduty.NewFromConfig(cfg).ListDetectors(ctx, &guardduty.ListDetectorsInput{})
	require.NoError(t, err)
	assert.NotEmpty(t, gd.DetectorIds, "GuardDuty detector")

	trails, err := cloudtrail.NewFromConfig(cfg).DescribeTrails(ctx, &cloudtrail.DescribeTrailsInput{TrailNameList: []string{"hive-account-trail"}})
	require.NoError(t, err)
	require.Len(t, trails.TrailList, 1)
	assert.True(t, aws.ToBool(trails.TrailList[0].IsMultiRegionTrail))
	assert.True(t, aws.ToBool(trails.TrailList[0].LogFileValidationEnabled))

	rec, err := configservice.NewFromConfig(cfg).DescribeConfigurationRecorders(ctx, &configservice.DescribeConfigurationRecordersInput{})
	require.NoError(t, err)
	require.NotEmpty(t, rec.ConfigurationRecorders)
	rg := rec.ConfigurationRecorders[0].RecordingGroup
	assert.False(t, rg.AllSupported, "Config must be limited to this build's resource types")
	assert.Contains(t, rg.ResourceTypes, cfgtypes.ResourceType("AWS::RDS::DBInstance"))
}

// --- network ---------------------------------------------------------------

type networkIDs struct {
	vpc                     string
	appSubnets, dataSubnets []string
	albSG, appSG, dbSG      string
}

func checkNetwork(t *testing.T, cfg aws.Config) networkIDs {
	c := ec2.NewFromConfig(cfg)
	var ids networkIDs

	vpcs, err := c.DescribeVpcs(ctx, &ec2.DescribeVpcsInput{Filters: []ec2types.Filter{{Name: aws.String("tag:Name"), Values: []string{"hive-uat"}}}})
	require.NoError(t, err)
	require.Len(t, vpcs.Vpcs, 1)
	assert.Equal(t, "10.20.0.0/16", aws.ToString(vpcs.Vpcs[0].CidrBlock))
	ids.vpc = aws.ToString(vpcs.Vpcs[0].VpcId)

	// Subnets: three tiers in two AZs, with the plan's ranges.
	want := map[string]string{
		"hive-uat-public-ap-south-1a": "10.20.0.0/24", "hive-uat-public-ap-south-1b": "10.20.1.0/24",
		"hive-uat-app-ap-south-1a": "10.20.16.0/22", "hive-uat-app-ap-south-1b": "10.20.20.0/22",
		"hive-uat-data-ap-south-1a": "10.20.32.0/24", "hive-uat-data-ap-south-1b": "10.20.33.0/24",
	}
	subnets, err := c.DescribeSubnets(ctx, &ec2.DescribeSubnetsInput{Filters: []ec2types.Filter{{Name: aws.String("vpc-id"), Values: []string{ids.vpc}}}})
	require.NoError(t, err)
	got := map[string]string{}
	for _, s := range subnets.Subnets {
		name := tag(s.Tags, "Name")
		got[name] = aws.ToString(s.CidrBlock)
		assert.False(t, aws.ToBool(s.MapPublicIpOnLaunch), "%s must not assign public IPs", name)
		switch {
		case strings.HasPrefix(name, "hive-uat-app-"):
			ids.appSubnets = append(ids.appSubnets, aws.ToString(s.SubnetId))
		case strings.HasPrefix(name, "hive-uat-data-"):
			ids.dataSubnets = append(ids.dataSubnets, aws.ToString(s.SubnetId))
		}
	}
	assert.Equal(t, want, got)

	// Routes: public -> internet gateway, app -> NAT, data -> nothing outside the VPC.
	assert.True(t, strings.HasPrefix(defaultRouteTarget(t, c, "hive-uat-public"), "igw-"), "public subnets route to the internet gateway")
	assert.True(t, strings.HasPrefix(defaultRouteTarget(t, c, "hive-uat-app"), "nat-"), "app subnets route through the NAT gateway")
	assert.Empty(t, defaultRouteTarget(t, c, "hive-uat-data"), "data subnets must have no route out of the VPC")

	// Security groups: each tier talks only to the next.
	ids.albSG = securityGroupID(t, c, "hive-uat-alb-sg")
	ids.appSG = securityGroupID(t, c, "hive-uat-app-sg")
	ids.dbSG = securityGroupID(t, c, "hive-uat-db-sg")

	in, out := rules(t, c, ids.dbSG)
	assert.Equal(t, []string{"tcp 5432-5432 from " + ids.appSG}, in, "db-sg accepts PostgreSQL from app-sg only")
	assert.Empty(t, out, "db-sg has no outbound rules")

	in, out = rules(t, c, ids.appSG)
	assert.ElementsMatch(t, []string{"tcp 8000-8000 from " + ids.albSG, "tcp 8080-8080 from " + ids.albSG}, in, "app-sg accepts the app ports from alb-sg only")
	assert.ElementsMatch(t, []string{"tcp 443-443 to 0.0.0.0/0", "tcp 5432-5432 to " + ids.dbSG}, out, "app-sg reaches HTTPS outside and the database only")

	in, out = rules(t, c, ids.albSG)
	assert.ElementsMatch(t, []string{"tcp 443-443 from 0.0.0.0/0", "tcp 80-80 from 0.0.0.0/0"}, in)
	assert.ElementsMatch(t, []string{"tcp 8000-8000 to " + ids.appSG, "tcp 8080-8080 to " + ids.appSG}, out)

	// S3 gateway endpoint and flow logs.
	eps, err := c.DescribeVpcEndpoints(ctx, &ec2.DescribeVpcEndpointsInput{Filters: []ec2types.Filter{{Name: aws.String("vpc-id"), Values: []string{ids.vpc}}}})
	require.NoError(t, err)
	require.Len(t, eps.VpcEndpoints, 1)
	assert.Equal(t, ec2types.VpcEndpointTypeGateway, eps.VpcEndpoints[0].VpcEndpointType)
	assert.True(t, strings.HasSuffix(aws.ToString(eps.VpcEndpoints[0].ServiceName), ".s3"))

	fl, err := c.DescribeFlowLogs(ctx, &ec2.DescribeFlowLogsInput{Filter: []ec2types.Filter{{Name: aws.String("resource-id"), Values: []string{ids.vpc}}}})
	require.NoError(t, err)
	assert.Len(t, fl.FlowLogs, 1, "VPC flow logs")

	// Three customer-managed keys, all rotating.
	k := kms.NewFromConfig(cfg)
	for _, purpose := range []string{"rds", "storage", "app"} {
		key, err := k.DescribeKey(ctx, &kms.DescribeKeyInput{KeyId: aws.String("alias/hive-uat-" + purpose)})
		require.NoError(t, err, "KMS key %s", purpose)
		rot, err := k.GetKeyRotationStatus(ctx, &kms.GetKeyRotationStatusInput{KeyId: key.KeyMetadata.KeyId})
		require.NoError(t, err)
		assert.True(t, rot.KeyRotationEnabled, "KMS key %s rotates", purpose)
	}
	return ids
}

// --- data ------------------------------------------------------------------

func checkData(t *testing.T, cfg aws.Config, net networkIDs) {
	out, err := rds.NewFromConfig(cfg).DescribeDBInstances(ctx, &rds.DescribeDBInstancesInput{DBInstanceIdentifier: aws.String("hive-uat-postgres")})
	require.NoError(t, err)
	require.Len(t, out.DBInstances, 1)
	db := out.DBInstances[0]

	assert.False(t, aws.ToBool(db.PubliclyAccessible), "database must not be publicly accessible")
	assert.True(t, aws.ToBool(db.StorageEncrypted), "database storage must be encrypted")
	assert.NotEmpty(t, aws.ToString(db.KmsKeyId), "database uses the customer-managed key")
	assert.Equal(t, "postgres", aws.ToString(db.Engine))
	assert.True(t, strings.HasPrefix(aws.ToString(db.EngineVersion), "17"), "PostgreSQL 17")
	assert.Equal(t, "db.t4g.medium", aws.ToString(db.DBInstanceClass))
	assert.False(t, aws.ToBool(db.MultiAZ), "Single-AZ for UAT")
	assert.EqualValues(t, 14, aws.ToInt32(db.BackupRetentionPeriod), "14-day point-in-time recovery")
	assert.True(t, aws.ToBool(db.DeletionProtection))

	require.NotNil(t, db.DBSubnetGroup)
	for _, s := range db.DBSubnetGroup.Subnets {
		assert.Contains(t, net.dataSubnets, aws.ToString(s.SubnetIdentifier), "database lives in the data subnets")
	}
	var sgs []string
	for _, g := range db.VpcSecurityGroups {
		sgs = append(sgs, aws.ToString(g.VpcSecurityGroupId))
	}
	assert.Equal(t, []string{net.dbSG}, sgs, "database uses db-sg only")
}

// --- platform --------------------------------------------------------------

func checkPlatform(t *testing.T, cfg aws.Config) {
	// ALB: HTTPS with TLS 1.2/1.3, HTTP redirected, logs on, invalid headers dropped.
	lbc := elb.NewFromConfig(cfg)
	lbs, err := lbc.DescribeLoadBalancers(ctx, &elb.DescribeLoadBalancersInput{Names: []string{"hive-uat"}})
	require.NoError(t, err)
	require.Len(t, lbs.LoadBalancers, 1)
	alb := lbs.LoadBalancers[0]
	assert.Equal(t, "internet-facing", string(alb.Scheme))

	ls, err := lbc.DescribeListeners(ctx, &elb.DescribeListenersInput{LoadBalancerArn: alb.LoadBalancerArn})
	require.NoError(t, err)
	ports := map[int32]string{}
	for _, l := range ls.Listeners {
		ports[aws.ToInt32(l.Port)] = string(l.DefaultActions[0].Type)
		if aws.ToInt32(l.Port) == 443 {
			assert.Equal(t, "ELBSecurityPolicy-TLS13-1-2-2021-06", aws.ToString(l.SslPolicy))
		}
	}
	assert.Equal(t, map[int32]string{443: "fixed-response", 80: "redirect"}, ports)

	attrs, err := lbc.DescribeLoadBalancerAttributes(ctx, &elb.DescribeLoadBalancerAttributesInput{LoadBalancerArn: alb.LoadBalancerArn})
	require.NoError(t, err)
	a := map[string]string{}
	for _, x := range attrs.Attributes {
		a[aws.ToString(x.Key)] = aws.ToString(x.Value)
	}
	assert.Equal(t, "true", a["access_logs.s3.enabled"], "ALB access logs")
	assert.Equal(t, "true", a["routing.http.drop_invalid_header_fields.enabled"])
	assert.Equal(t, "true", a["deletion_protection.enabled"])

	// WAF: three managed groups and a rate rule, all counting during the first UAT week.
	w := wafv2.NewFromConfig(cfg)
	acls, err := w.ListWebACLs(ctx, &wafv2.ListWebACLsInput{Scope: waftypes.ScopeRegional})
	require.NoError(t, err)
	var acl *waftypes.WebACL
	for _, s := range acls.WebACLs {
		if aws.ToString(s.Name) == "hive-uat" {
			got, err := w.GetWebACL(ctx, &wafv2.GetWebACLInput{Name: s.Name, Id: s.Id, Scope: waftypes.ScopeRegional})
			require.NoError(t, err)
			acl = got.WebACL
		}
	}
	require.NotNil(t, acl, "web ACL hive-uat")
	names := map[string]bool{}
	for _, r := range acl.Rules {
		names[aws.ToString(r.Name)] = true
		if r.OverrideAction != nil {
			assert.NotNil(t, r.OverrideAction.Count, "%s counts in UAT week one", aws.ToString(r.Name))
		} else {
			assert.NotNil(t, r.Action.Count, "%s counts in UAT week one", aws.ToString(r.Name))
		}
	}
	assert.Equal(t, map[string]bool{
		"AWSManagedRulesCommonRuleSet": true, "AWSManagedRulesKnownBadInputsRuleSet": true,
		"AWSManagedRulesAmazonIpReputationList": true, "rate-limit-per-ip": true,
	}, names)
	assoc, err := w.GetWebACLForResource(ctx, &wafv2.GetWebACLForResourceInput{ResourceArn: alb.LoadBalancerArn})
	require.NoError(t, err)
	require.NotNil(t, assoc.WebACL, "WAF must be attached to the ALB")
	assert.Equal(t, "hive-uat", aws.ToString(assoc.WebACL.Name))

	// ECR: immutable tags, scan on push, KMS.
	repos, err := ecr.NewFromConfig(cfg).DescribeRepositories(ctx, &ecr.DescribeRepositoriesInput{
		RepositoryNames: []string{"hive-uat/hiveconnect-api", "hive-uat/prism"},
	})
	require.NoError(t, err)
	require.Len(t, repos.Repositories, 2)
	for _, r := range repos.Repositories {
		assert.Equal(t, "IMMUTABLE", string(r.ImageTagMutability), aws.ToString(r.RepositoryName))
		assert.True(t, r.ImageScanningConfiguration.ScanOnPush, aws.ToString(r.RepositoryName))
		assert.Equal(t, "KMS", string(r.EncryptionConfiguration.EncryptionType), aws.ToString(r.RepositoryName))
	}

	// Buckets: private, versioned, TLS-only; app data on the KMS key, ALB logs on SSE-S3.
	for _, b := range []string{"certificates", "documents", "firmware", "images"} {
		checkPrivateBucket(t, cfg, "hive-uat-"+b+"-"+flociAccount, "aws:kms")
	}
	checkPrivateBucket(t, cfg, "hive-uat-alb-logs-"+flociAccount, "AES256")
	checkPrivateBucket(t, cfg, "aws-waf-logs-hive-uat-"+flociAccount, "aws:kms")

	// Secrets: the eight credentials, empty, on the app key.
	sm := secretsmanager.NewFromConfig(cfg)
	sec, err := sm.ListSecrets(ctx, &secretsmanager.ListSecretsInput{
		Filters: []smtypes.Filter{{Key: smtypes.FilterNameStringTypeName, Values: []string{"hive-uat/"}}},
	})
	require.NoError(t, err)
	var secretNames []string
	for _, s := range sec.SecretList {
		secretNames = append(secretNames, aws.ToString(s.Name))
		assert.NotEmpty(t, aws.ToString(s.KmsKeyId), "%s is on the customer-managed key", aws.ToString(s.Name))
	}
	assert.ElementsMatch(t, []string{
		"hive-uat/db-hiveconnect", "hive-uat/db-prism", "hive-uat/elastic-apm", "hive-uat/smtp",
		"hive-uat/email", "hive-uat/whatsapp", "hive-uat/oauth", "hive-uat/messaging",
	}, secretNames)

	// Alerts: encrypted topic, every alarm the plan lists, the budget.
	topic, err := sns.NewFromConfig(cfg).GetTopicAttributes(ctx, &sns.GetTopicAttributesInput{
		TopicArn: aws.String("arn:aws:sns:" + region + ":" + flociAccount + ":hive-uat-alerts"),
	})
	require.NoError(t, err)
	assert.NotEmpty(t, topic.Attributes["KmsMasterKeyId"], "alert topic is encrypted")

	alarms := alarmNames(t, cfg)
	for _, n := range []string{
		"hive-uat-alb-5xx", "hive-uat-app-5xx", "hive-uat-nat-port-allocation-errors",
		"hive-uat-db-cpu-high", "hive-uat-db-cpu-credits-low", "hive-uat-db-surplus-credits-charged",
		"hive-uat-db-free-storage-low", "hive-uat-db-connections-high", "hive-uat-db-iops-near-limit",
	} {
		assert.Contains(t, alarms, n)
	}

	bud, err := budgets.NewFromConfig(cfg).DescribeBudget(ctx, &budgets.DescribeBudgetInput{
		AccountId: aws.String(flociAccount), BudgetName: aws.String("hive-uat-monthly"),
	})
	require.NoError(t, err)
	amount, _ := strconv.ParseFloat(aws.ToString(bud.Budget.BudgetLimit.Amount), 64)
	assert.EqualValues(t, 230, amount, "UAT budget is $230")
}

// --- apps ------------------------------------------------------------------

func checkApps(t *testing.T, cfg aws.Config, net networkIDs) {
	c := ecs.NewFromConfig(cfg)

	cl, err := c.DescribeClusters(ctx, &ecs.DescribeClustersInput{Clusters: []string{"hive-uat"}})
	require.NoError(t, err)
	require.Len(t, cl.Clusters, 1)
	assert.ElementsMatch(t, []string{"FARGATE", "FARGATE_SPOT"}, cl.Clusters[0].CapacityProviders)

	svcs, err := c.DescribeServices(ctx, &ecs.DescribeServicesInput{Cluster: aws.String("hive-uat"), Services: []string{"hiveconnect-api", "prism"}})
	require.NoError(t, err)
	require.Len(t, svcs.Services, 2)

	sizes := map[string][2]string{"hiveconnect-api": {"1024", "2048"}, "prism": {"512", "1024"}}
	for _, s := range svcs.Services {
		name := aws.ToString(s.ServiceName)

		// One on-demand task; everything above it on Spot.
		strategy := map[string][2]int32{}
		for _, p := range s.CapacityProviderStrategy {
			strategy[aws.ToString(p.CapacityProvider)] = [2]int32{p.Base, p.Weight}
		}
		assert.Equal(t, map[string][2]int32{"FARGATE": {1, 0}, "FARGATE_SPOT": {0, 1}}, strategy, "%s: base 1 on-demand, Spot above", name)

		assert.True(t, s.EnableExecuteCommand, "%s: ECS Exec instead of SSH", name)
		require.NotNil(t, s.DeploymentConfiguration.DeploymentCircuitBreaker)
		assert.True(t, s.DeploymentConfiguration.DeploymentCircuitBreaker.Rollback, "%s: failed deploys roll back", name)
		vpc := s.NetworkConfiguration.AwsvpcConfiguration
		assert.Equal(t, ecstypes.AssignPublicIpDisabled, vpc.AssignPublicIp, "%s: no public IP", name)
		assert.Equal(t, []string{net.appSG}, vpc.SecurityGroups, "%s: app-sg", name)
		assert.Subset(t, net.appSubnets, vpc.Subnets, "%s: app subnets", name)

		td, err := c.DescribeTaskDefinition(ctx, &ecs.DescribeTaskDefinitionInput{TaskDefinition: s.TaskDefinition})
		require.NoError(t, err)
		def := td.TaskDefinition
		assert.Equal(t, ecstypes.CPUArchitectureArm64, def.RuntimePlatform.CpuArchitecture, "%s: Graviton", name)
		assert.Equal(t, sizes[name][0], aws.ToString(def.Cpu), "%s cpu", name)
		assert.Equal(t, sizes[name][1], aws.ToString(def.Memory), "%s memory", name)
		ctr := def.ContainerDefinitions[0]
		assert.EqualValues(t, 120, aws.ToInt32(ctr.StopTimeout), "%s: 120 s to drain on SIGTERM", name)
		for _, sec := range ctr.Secrets {
			assert.Contains(t, aws.ToString(sec.ValueFrom), ":secret:hive-uat/", "%s: %s comes from Secrets Manager", name, aws.ToString(sec.Name))
		}
		for _, e := range ctr.Environment {
			assert.NotContains(t, []string{"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "REDIS_URL", "REDIS_HOST"}, aws.ToString(e.Name), "%s: no keys or Redis settings", name)
		}

		checkRoleBoundary(t, cfg, "hive-uat-"+name+"-task")
		checkRoleBoundary(t, cfg, "hive-uat-"+name+"-exec")
		checkTargetGroup(t, cfg, "hive-uat-"+name)
	}
	checkRoleBoundary(t, cfg, "hive-uat-vpc-flow-logs")
	checkRoleBoundary(t, cfg, "hive-uat-postgres-monitoring")
	checkRoleBoundary(t, cfg, "hive-uat-db-admin-task")

	// Autoscaling: 1-2 tasks each in UAT, CPU 60% and requests-per-target policies.
	as := applicationautoscaling.NewFromConfig(cfg)
	targets, err := as.DescribeScalableTargets(ctx, &applicationautoscaling.DescribeScalableTargetsInput{ServiceNamespace: aastypes.ServiceNamespaceEcs})
	require.NoError(t, err)
	caps := map[string][2]int32{}
	for _, x := range targets.ScalableTargets {
		caps[aws.ToString(x.ResourceId)] = [2]int32{aws.ToInt32(x.MinCapacity), aws.ToInt32(x.MaxCapacity)}
	}
	assert.Equal(t, [2]int32{1, 2}, caps["service/hive-uat/hiveconnect-api"])
	assert.Equal(t, [2]int32{1, 2}, caps["service/hive-uat/prism"])

	pol, err := as.DescribeScalingPolicies(ctx, &applicationautoscaling.DescribeScalingPoliciesInput{ServiceNamespace: aastypes.ServiceNamespaceEcs})
	require.NoError(t, err)
	var policies []string
	for _, p := range pol.ScalingPolicies {
		policies = append(policies, aws.ToString(p.PolicyName))
	}
	assert.ElementsMatch(t, []string{
		"hive-uat-hiveconnect-api-cpu", "hive-uat-hiveconnect-api-requests", "hive-uat-prism-cpu", "hive-uat-prism-requests",
	}, policies)

	// Per-service alarms.
	alarms := alarmNames(t, cfg)
	for _, s := range []string{"hiveconnect-api", "prism"} {
		for _, a := range []string{"cpu-high", "healthy-tasks-below-minimum", "unhealthy-targets"} {
			assert.Contains(t, alarms, "hive-uat-"+s+"-"+a)
		}
	}

	// db-admin task for psql through ECS Exec.
	td, err := c.DescribeTaskDefinition(ctx, &ecs.DescribeTaskDefinitionInput{TaskDefinition: aws.String("hive-uat-db-admin")})
	require.NoError(t, err)
	assert.Equal(t, ecstypes.CPUArchitectureArm64, td.TaskDefinition.RuntimePlatform.CpuArchitecture)
}

// --- small helpers -----------------------------------------------------------

func tag(tags []ec2types.Tag, key string) string {
	for _, t := range tags {
		if aws.ToString(t.Key) == key {
			return aws.ToString(t.Value)
		}
	}
	return ""
}

// defaultRouteTarget returns where 0.0.0.0/0 goes in the named route table ("" if nowhere).
func defaultRouteTarget(t *testing.T, c *ec2.Client, name string) string {
	t.Helper()
	out, err := c.DescribeRouteTables(ctx, &ec2.DescribeRouteTablesInput{Filters: []ec2types.Filter{{Name: aws.String("tag:Name"), Values: []string{name}}}})
	require.NoError(t, err)
	require.Len(t, out.RouteTables, 1, name)
	for _, r := range out.RouteTables[0].Routes {
		if aws.ToString(r.DestinationCidrBlock) == "0.0.0.0/0" {
			if r.NatGatewayId != nil {
				return aws.ToString(r.NatGatewayId)
			}
			return aws.ToString(r.GatewayId)
		}
	}
	return ""
}

func securityGroupID(t *testing.T, c *ec2.Client, name string) string {
	t.Helper()
	out, err := c.DescribeSecurityGroups(ctx, &ec2.DescribeSecurityGroupsInput{Filters: []ec2types.Filter{{Name: aws.String("group-name"), Values: []string{name}}}})
	require.NoError(t, err)
	require.Len(t, out.SecurityGroups, 1, name)
	return aws.ToString(out.SecurityGroups[0].GroupId)
}

// rules lists a group's rules as "proto from-to from|to source". AWS's default
// unlabelled allow-all egress rule, which Floci fails to remove, is skipped.
func rules(t *testing.T, c *ec2.Client, groupID string) (ingress, egress []string) {
	t.Helper()
	out, err := c.DescribeSecurityGroups(ctx, &ec2.DescribeSecurityGroupsInput{GroupIds: []string{groupID}})
	require.NoError(t, err)
	g := out.SecurityGroups[0]
	render := func(perms []ec2types.IpPermission, dir string) []string {
		var res []string
		for _, p := range perms {
			proto := aws.ToString(p.IpProtocol)
			ports := strconv.Itoa(int(aws.ToInt32(p.FromPort))) + "-" + strconv.Itoa(int(aws.ToInt32(p.ToPort)))
			for _, r := range p.IpRanges {
				if dir == "to" && proto == "-1" && aws.ToString(r.CidrIp) == "0.0.0.0/0" && aws.ToString(r.Description) == "" {
					continue // Floci gap: default egress rule not revoked
				}
				res = append(res, proto+" "+ports+" "+dir+" "+aws.ToString(r.CidrIp))
			}
			for _, u := range p.UserIdGroupPairs {
				res = append(res, proto+" "+ports+" "+dir+" "+aws.ToString(u.GroupId))
			}
		}
		return res
	}
	return render(g.IpPermissions, "from"), render(g.IpPermissionsEgress, "to")
}

func checkPrivateBucket(t *testing.T, cfg aws.Config, bucket, sse string) {
	t.Helper()
	c := s3.NewFromConfig(cfg, func(o *s3.Options) { o.UsePathStyle = true })

	bpa, err := c.GetPublicAccessBlock(ctx, &s3.GetPublicAccessBlockInput{Bucket: aws.String(bucket)})
	require.NoError(t, err, bucket)
	p := bpa.PublicAccessBlockConfiguration
	assert.True(t, aws.ToBool(p.BlockPublicAcls) && aws.ToBool(p.BlockPublicPolicy) && aws.ToBool(p.IgnorePublicAcls) && aws.ToBool(p.RestrictPublicBuckets), "%s blocks public access", bucket)

	v, err := c.GetBucketVersioning(ctx, &s3.GetBucketVersioningInput{Bucket: aws.String(bucket)})
	require.NoError(t, err, bucket)
	assert.Equal(t, "Enabled", string(v.Status), "%s is versioned", bucket)

	enc, err := c.GetBucketEncryption(ctx, &s3.GetBucketEncryptionInput{Bucket: aws.String(bucket)})
	require.NoError(t, err, bucket)
	assert.Equal(t, sse, string(enc.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm), "%s encryption", bucket)

	assert.Contains(t, bucketPolicy(t, cfg, bucket), "DenyInsecureTransport", "%s is TLS-only", bucket)
}

func bucketPolicy(t *testing.T, cfg aws.Config, bucket string) string {
	t.Helper()
	c := s3.NewFromConfig(cfg, func(o *s3.Options) { o.UsePathStyle = true })
	pol, err := c.GetBucketPolicy(ctx, &s3.GetBucketPolicyInput{Bucket: aws.String(bucket)})
	require.NoError(t, err, bucket)
	return aws.ToString(pol.Policy)
}

func policyDocument(t *testing.T, c *iam.Client, arn string) string {
	t.Helper()
	p, err := c.GetPolicy(ctx, &iam.GetPolicyInput{PolicyArn: aws.String(arn)})
	require.NoError(t, err)
	v, err := c.GetPolicyVersion(ctx, &iam.GetPolicyVersionInput{PolicyArn: aws.String(arn), VersionId: p.Policy.DefaultVersionId})
	require.NoError(t, err)
	doc, err := url.QueryUnescape(aws.ToString(v.PolicyVersion.Document))
	require.NoError(t, err)
	var parsed map[string]any
	require.NoError(t, json.Unmarshal([]byte(doc), &parsed), "boundary is valid JSON")
	return doc
}

func checkRoleBoundary(t *testing.T, cfg aws.Config, name string) {
	t.Helper()
	r, err := iam.NewFromConfig(cfg).GetRole(ctx, &iam.GetRoleInput{RoleName: aws.String(name)})
	require.NoError(t, err, name)
	require.NotNil(t, r.Role.PermissionsBoundary, "%s must carry the permission boundary", name)
	assert.Equal(t, "arn:aws:iam::"+flociAccount+":policy/hive-boundary", aws.ToString(r.Role.PermissionsBoundary.PermissionsBoundaryArn), name)
}

func checkTargetGroup(t *testing.T, cfg aws.Config, name string) {
	t.Helper()
	c := elb.NewFromConfig(cfg)
	tg, err := c.DescribeTargetGroups(ctx, &elb.DescribeTargetGroupsInput{Names: []string{name}})
	require.NoError(t, err, name)
	g := tg.TargetGroups[0]
	assert.Equal(t, "/healthz", aws.ToString(g.HealthCheckPath), name)
	assert.Equal(t, "ip", string(g.TargetType), name)
	attrs, err := c.DescribeTargetGroupAttributes(ctx, &elb.DescribeTargetGroupAttributesInput{TargetGroupArn: g.TargetGroupArn})
	require.NoError(t, err)
	for _, a := range attrs.Attributes {
		if aws.ToString(a.Key) == "deregistration_delay.timeout_seconds" {
			assert.Equal(t, "60", aws.ToString(a.Value), "%s drains for 60 s", name)
		}
	}
}

func alarmNames(t *testing.T, cfg aws.Config) []string {
	t.Helper()
	out, err := cloudwatch.NewFromConfig(cfg).DescribeAlarms(ctx, &cloudwatch.DescribeAlarmsInput{AlarmNamePrefix: aws.String("hive-uat-"), MaxRecords: aws.Int32(100)})
	require.NoError(t, err)
	var names []string
	for _, a := range out.MetricAlarms {
		names = append(names, aws.ToString(a.AlarmName))
	}
	return names
}
