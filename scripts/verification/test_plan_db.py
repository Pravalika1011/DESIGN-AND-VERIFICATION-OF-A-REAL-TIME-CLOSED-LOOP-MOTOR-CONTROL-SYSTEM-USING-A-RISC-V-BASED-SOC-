# scripts/test_plan_db.py
# Phase 5 Authoritative Test Plan Database
# Assembles all test cases across all 20 categories.

import sys
import os

TEST_CASES = []

def add_tc(cat_id, name, desc, checkpoints, scope, path, c_desc, c_out, sv_desc, sv_out, ext_if, ext_in, ext_out, rtl_mod, feature, reg_addr, method, cov_target):
    TEST_CASES.append({
        "cat_id": cat_id,
        "name": name,
        "desc": desc,
        "checkpoints": checkpoints,
        "scope": scope,
        "path": path,
        "c_desc": c_desc,
        "c_out": c_out,
        "sv_desc": sv_desc,
        "sv_out": sv_out,
        "ext_if": ext_if,
        "ext_in": ext_in,
        "ext_out": ext_out,
        "rtl_mod": rtl_mod,
        "feature": feature,
        "reg_addr": reg_addr,
        "method": method,
        "cov_target": cov_target
    })

# Populate all parts
from test_plan_part1 import populate_part1
from test_plan_part2 import populate_part2
from test_plan_part3 import populate_part3
from test_plan_part4 import populate_part4
from test_plan_part5 import populate_part5

populate_part1(add_tc)
populate_part2(add_tc)
populate_part3(add_tc)
populate_part4(add_tc)
populate_part5(add_tc)

if __name__ == "__main__":
    print(f"Total test cases loaded in test_plan_db: {len(TEST_CASES)}")
