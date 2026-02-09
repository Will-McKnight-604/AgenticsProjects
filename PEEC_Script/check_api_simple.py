#!/usr/bin/env python3
"""
Simple API checker using only built-in Python libraries (no requests needed)
"""

import urllib.request
import json
import sys

SERVER_URL = "http://localhost:8484"

print("="*60)
print("OpenMagnetics Server API Investigation")
print("="*60)

# Test 1: Get all wires
print("\nTest 1: Fetching /wires endpoint")
print("-"*60)
try:
    with urllib.request.urlopen(f"{SERVER_URL}/wires", timeout=5) as response:
        data = json.loads(response.read().decode())
        print(f"✓ Success! Got {len(data)} wires")

        # Find foil wires
        foil_wires = [k for k in data.keys() if 'foil' in k.lower()]
        print(f"Found {len(foil_wires)} foil wires")

        if foil_wires:
            # Show first foil wire from list endpoint
            test_wire = foil_wires[0]
            print(f"\nSample foil wire: {test_wire}")
            print(f"Fields from /wires: {list(data[test_wire].keys())}")
            print(f"Data: {json.dumps(data[test_wire], indent=2)}")

            # Test 2: Get detailed wire info
            print(f"\n\nTest 2: Fetching detailed info for {test_wire}")
            print("-"*60)
            try:
                url = f"{SERVER_URL}/wire/{test_wire}"
                with urllib.request.urlopen(url, timeout=5) as resp:
                    detailed = json.loads(resp.read().decode())
                    print(f"✓ Success!")
                    print(f"Fields from /wire/{{name}}: {list(detailed.keys())}")
                    print(f"Data: {json.dumps(detailed, indent=2)}")

                    # Compare
                    print("\n\n" + "="*60)
                    print("COMPARISON:")
                    print("="*60)
                    list_fields = set(data[test_wire].keys())
                    detail_fields = set(detailed.keys())

                    print(f"Fields in /wires only: {list_fields - detail_fields}")
                    print(f"Fields in /wire/{{name}} only: {detail_fields - list_fields}")

                    # Check for dimensional fields
                    dim_fields = ['foil_width', 'foil_thickness', 'rect_width', 'rect_height',
                                  'width', 'thickness', 'conducting_width', 'conducting_height']
                    found_dims = [f for f in dim_fields if f in detailed]

                    if found_dims:
                        print(f"\n✓ FOUND dimensional fields in /wire/{{name}}: {found_dims}")
                        for f in found_dims:
                            print(f"  {f} = {detailed[f]}")
                    else:
                        print(f"\n✗ NO dimensional fields found in either endpoint")

            except urllib.error.HTTPError as e:
                print(f"✗ HTTP Error {e.code}: {e.reason}")
            except Exception as e:
                print(f"✗ Error: {e}")
        else:
            print("No foil wires found")

except urllib.error.URLError as e:
    print(f"✗ Cannot connect to server: {e}")
    print("Make sure the server is running with: python om_server.py")
except Exception as e:
    print(f"✗ Error: {e}")

print("\n" + "="*60)
