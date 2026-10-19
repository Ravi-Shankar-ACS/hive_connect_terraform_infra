#!/bin/bash
# Appendix price check (read-only). Run in CloudShell; prints Mumbai's published
# prices for RDS PostgreSQL (db.t4g.medium, gp3) and Fargate on-demand and Spot
# into ~/iotiq-snapshot/prices-uat.txt, to replace the estimates in the cost plan.
export AWS_PAGER=""
mkdir -p ~/iotiq-snapshot
exec > ~/iotiq-snapshot/prices-uat.txt 2>&1
python3 - << 'PY'
import json, subprocess
LOC = "Asia Pacific (Mumbai)"
def products(service, extra=None):
    cmd = ["aws", "pricing", "get-products", "--service-code", service, "--region", "us-east-1",
           "--filters", f"Type=TERM_MATCH,Field=location,Value={LOC}"]
    for k, v in (extra or {}).items():
        cmd.append(f"Type=TERM_MATCH,Field={k},Value={v}")
    cmd += ["--output", "json"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR", service, r.stderr.strip()[:300])
        return []
    return [json.loads(s) for s in json.loads(r.stdout).get("PriceList", [])]
def show(items, keep, label):
    for p in items:
        a = p["product"]["attributes"]
        if not keep(a):
            continue
        for t in p["terms"].get("OnDemand", {}).values():
            for d in t["priceDimensions"].values():
                print(f"  {label(a):46} {d['pricePerUnit'].get('USD','?'):>12} per {d['unit']:9} {d['description'][:50]}")
print("== RDS PostgreSQL: db.t4g.medium and gp3 storage (Mumbai) ==")
rds = products("AmazonRDS", {"databaseEngine": "PostgreSQL"})
print("products returned:", len(rds))
show(rds, lambda a: a.get("instanceType") == "db.t4g.medium" or "gp3" in (a.get("usagetype", "") + a.get("volumeType", "")).lower(),
     lambda a: (a.get("instanceType", "") + " " + a.get("deploymentOption", "") + " " + a.get("usagetype", ""))[:46])
print("\n== ECS Fargate, Linux, on-demand and Spot (Mumbai) ==")
ecs = products("AmazonECS")
print("products returned:", len(ecs))
show(ecs, lambda a: "Fargate" in a.get("usagetype", "") and "Windows" not in a.get("usagetype", ""), lambda a: a.get("usagetype", "")[:46])
PY
echo "DONE"
