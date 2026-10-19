package test

// Helpers that point the real stacks at Floci, a local AWS emulator.
//
// The repository is copied to a temporary folder first, so nothing in the
// working tree changes. In the copy, small *_override.tf files (a standard
// Terraform feature) add the Floci endpoint to the AWS provider, the S3
// backend and the terraform_remote_state lookups. The stacks, modules and
// envs/uat values themselves run unchanged; only account_id is replaced with
// Floci's account.

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/gruntwork-io/terratest/modules/files"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

const (
	flociAccount = "000000000000"
	region       = "ap-south-1"
	env          = "uat"
	zoneName     = "iotiqinnovations.com"
)

func flociEndpoint() string {
	if v := os.Getenv("FLOCI_ENDPOINT"); v != "" {
		return v
	}
	return "http://localhost:4566"
}

// awsConfig returns an SDK config that talks to Floci.
func awsConfig(t *testing.T) aws.Config {
	t.Helper()
	cfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion(region),
		config.WithBaseEndpoint(flociEndpoint()),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("test", "test", "")),
	)
	require.NoError(t, err)
	return cfg
}

// requireFloci fails fast with a helpful message when the emulator is not up.
func requireFloci(t *testing.T) {
	t.Helper()
	client := http.Client{Timeout: 5 * time.Second}
	for i := 0; i < 30; i++ {
		resp, err := client.Get(flociEndpoint())
		if err == nil {
			resp.Body.Close()
			return
		}
		time.Sleep(2 * time.Second)
	}
	t.Fatalf("Floci is not answering on %s. Start it with: docker compose -f tests/docker-compose.yml up -d", flociEndpoint())
}

// copyRepo copies the repository (the parent of tests/) to a temp folder.
func copyRepo(t *testing.T) string {
	t.Helper()
	src, err := filepath.Abs("..")
	require.NoError(t, err)
	dst := filepath.Join(t.TempDir(), "repo")
	require.NoError(t, os.MkdirAll(dst, 0o755))
	require.NoError(t, files.CopyFolderContentsWithFilter(src, dst, func(path string) bool {
		base := filepath.Base(path)
		switch {
		case base == ".terraform", base == ".plans", base == ".git", base == "tests":
			return false
		case strings.HasSuffix(base, ".tfstate"), strings.HasSuffix(base, ".tfplan"):
			return false
		}
		return true
	}))
	return dst
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(t, os.WriteFile(path, []byte(content), 0o644))
}

// replaceAccountID swaps the placeholder account in every tfvars file of the copy.
func replaceAccountID(t *testing.T, repo string) {
	t.Helper()
	re := regexp.MustCompile(`123456789012`)
	require.NoError(t, filepath.Walk(filepath.Join(repo, "envs"), func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(p, ".tfvars") {
			return err
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(p, re.ReplaceAll(b, []byte(flociAccount)), 0o644)
	}))
}

// Services the stacks call, mapped to Floci.
var providerEndpoints = []string{
	"accessanalyzer", "acm", "appautoscaling", "budgets", "ce", "cloudtrail", "cloudwatch",
	"configservice", "ec2", "ecr", "ecs", "elbv2", "events", "guardduty", "iam", "inspector2",
	"iot", "kms", "logs", "rds", "route53", "s3", "secretsmanager", "sns", "sts", "wafv2",
}

// S3 Control puts the account ID in front of the host name
// (000000000000.<host>), which Windows cannot resolve for "localhost".
// localhost.localstack.cloud is a public DNS name whose every subdomain
// resolves to 127.0.0.1, so it reaches Floci on this machine.
func s3ControlEndpoint() string {
	if v := os.Getenv("FLOCI_S3CONTROL_ENDPOINT"); v != "" {
		return v
	}
	return "http://localhost.localstack.cloud:4566"
}

func providerOverride() string {
	var b strings.Builder
	b.WriteString("provider \"aws\" {\n")
	b.WriteString("  access_key                  = \"test\"\n")
	b.WriteString("  secret_key                  = \"test\"\n")
	b.WriteString("  skip_credentials_validation = true\n")
	b.WriteString("  skip_metadata_api_check     = true\n")
	b.WriteString("  skip_region_validation      = true\n")
	b.WriteString("  s3_use_path_style           = true\n")
	b.WriteString("  endpoints {\n")
	for _, e := range providerEndpoints {
		fmt.Fprintf(&b, "    %s = %q\n", e, flociEndpoint())
	}
	fmt.Fprintf(&b, "    s3control = %q\n", s3ControlEndpoint())
	b.WriteString("  }\n}\n")
	return b.String()
}

// s3StateSettings are the extra S3 settings Terraform needs to keep state in Floci.
func s3StateSettings() string {
	return fmt.Sprintf(`access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    endpoints = {
      s3  = %q
      sts = %q
    }`, flociEndpoint(), flociEndpoint())
}

func backendOverride() string {
	return fmt.Sprintf("terraform {\n  backend \"s3\" {\n    %s\n  }\n}\n", s3StateSettings())
}

func remoteStateOverride(name, key string) string {
	return fmt.Sprintf(`data "terraform_remote_state" %q {
  config = {
    bucket = "hive-tfstate-%s"
    key    = %q
    region = %q
    %s
  }
}
`, name, flociAccount, key, region, s3StateSettings())
}

// remoteStates lists the earlier layers each layer reads.
var remoteStates = map[string][]string{
	"network":  {},
	"data":     {"network"},
	"platform": {"network", "data"},
	"apps":     {"network", "data", "platform"},
}

// prepareCopy writes every override file into the temporary copy.
func prepareCopy(t *testing.T, repo string) {
	t.Helper()
	replaceAccountID(t, repo)

	writeFile(t, filepath.Join(repo, "bootstrap", "floci_override.tf"), providerOverride())
	writeFile(t, filepath.Join(repo, "account", "floci_override.tf"), providerOverride()+backendOverride())

	for layer, deps := range remoteStates {
		content := providerOverride() + backendOverride()
		for _, d := range deps {
			content += remoteStateOverride(d, fmt.Sprintf("%s/%s.tfstate", env, d))
		}
		writeFile(t, filepath.Join(repo, "stacks", layer, "floci_override.tf"), content)
	}

	// Bootstrap's tfvars are an example file in the repository.
	writeFile(t, filepath.Join(repo, "bootstrap", "terraform.tfvars"), fmt.Sprintf(
		"account_id = %q\nregion = %q\nbreak_glass_principal_arns = [\"arn:aws:iam::%s:user/test-admin\"]\n",
		flociAccount, region, flociAccount))
}

// stackOptions mirrors scripts/tf.sh: same var files, backend file and state key.
func stackOptions(t *testing.T, repo, target string) *terraform.Options {
	t.Helper()
	opts := &terraform.Options{
		NoColor: true,
		EnvVars: map[string]string{
			"AWS_ACCESS_KEY_ID":          "test",
			"AWS_SECRET_ACCESS_KEY":      "test",
			"AWS_REGION":                 region,
			"AWS_EC2_METADATA_DISABLED":  "true",
			"TF_IN_AUTOMATION":           "1",
		},
		RetryableTerraformErrors: map[string]string{".*connection reset.*": "Floci restarted a connection"},
		MaxRetries:               2,
		TimeBetweenRetries:       5 * time.Second,
	}

	switch target {
	case "bootstrap":
		opts.TerraformDir = filepath.Join(repo, "bootstrap")
	case "account":
		opts.TerraformDir = filepath.Join(repo, "account")
		opts.VarFiles = []string{"../envs/account.tfvars"}
		opts.BackendConfig = map[string]interface{}{"../envs/backend.hcl": nil, "key": "account/terraform.tfstate"}
		opts.Reconfigure = true
	default:
		layer := strings.TrimPrefix(target, env+"/")
		opts.TerraformDir = filepath.Join(repo, "stacks", layer)
		opts.VarFiles = []string{
			fmt.Sprintf("../../envs/%s/common.tfvars", env),
			fmt.Sprintf("../../envs/%s/%s.tfvars", env, layer),
		}
		opts.BackendConfig = map[string]interface{}{"../../envs/backend.hcl": nil, "key": fmt.Sprintf("%s/%s.tfstate", env, layer)}
		opts.Reconfigure = true
	}
	return opts
}
