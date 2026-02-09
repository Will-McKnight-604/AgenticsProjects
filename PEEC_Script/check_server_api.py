#!/usr/bin/env python3
"""
Check OpenMagnetics server API to understand available endpoints and data structure
"""

import requests
import json
import sys

SERVER_URL = "http://localhost:8484"

def print_json(data, indent=0):
    """Pretty print JSON with limited depth"""
    prefix = "  " * indent
    if isinstance(data, dict):
        for key, value in list(data.items())[:5]:  # Show first 5 items
            if isinstance(value, (dict, list)) and len(str(value)) > 100:
                print(f"{prefix}{key}: <{type(value).__name__} with {len(value)} items>")
            else:
                print(f"{prefix}{key}: {value}")
        if len(data) > 5:
            print(f"{prefix}... ({len(data)} total items)")
    else:
        print(f"{prefix}{data}")

def test_endpoint(path, description):
    """Test an API endpoint"""
    print(f"\n{'='*60}")
    print(f"Testing: {description}")
    print(f"Endpoint: {path}")
    print('='*60)

    try:
        response = requests.get(f"{SERVER_URL}{path}", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"Status: ✓ OK ({response.status_code})")
            print(f"Response type: {type(data).__name__}")

            if isinstance(data, dict):
                print(f"Keys ({len(data)}): {', '.join(list(data.keys())[:10])}")
                if len(data) > 10:
                    print(f"  ... and {len(data) - 10} more")

                # If it's a wire database, inspect first foil wire
                if 'Foil' in str(data.keys()):
                    foil_wires = [k for k in data.keys() if 'foil' in k.lower()]
                    if foil_wires:
                        sample_wire = foil_wires[0]
                        print(f"\nSample foil wire: {sample_wire}")
                        print("Fields:")
                        print_json(data[sample_wire], indent=1)
            else:
                print(f"Data: {data}")

        else:
            print(f"Status: ✗ ERROR ({response.status_code})")
    except requests.exceptions.ConnectionError:
        print("Status: ✗ Connection failed (server not running?)")
    except Exception as e:
        print(f"Status: ✗ Error: {e}")

def test_specific_wire(wire_name):
    """Test fetching a specific wire with detailed endpoint"""
    path = f"/wire/{wire_name}"
    print(f"\n{'='*60}")
    print(f"Testing: Detailed wire query")
    print(f"Endpoint: {path}")
    print('='*60)

    try:
        response = requests.get(f"{SERVER_URL}{path}", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"Status: ✓ OK ({response.status_code})")
            print(f"\nWire data for '{wire_name}':")
            print(json.dumps(data, indent=2))
        else:
            print(f"Status: ✗ ERROR ({response.status_code})")
            print(response.text)
    except Exception as e:
        print(f"Status: ✗ Error: {e}")

def main():
    print("="*60)
    print("OpenMagnetics Server API Investigation")
    print("="*60)

    # Test health
    test_endpoint("/health", "Server health check")

    # Test wires list
    test_endpoint("/wires", "All wires list")

    # Get a specific foil wire for detailed testing
    print("\nFetching wire list to find a foil wire...")
    try:
        resp = requests.get(f"{SERVER_URL}/wires", timeout=5)
        if resp.status_code == 200:
            wires = resp.json()
            foil_wires = [k for k in wires.keys() if 'foil' in k.lower()]
            if foil_wires:
                test_wire = foil_wires[0]
                print(f"Found test wire: {test_wire}")
                test_specific_wire(test_wire)
            else:
                print("No foil wires found in database")
    except Exception as e:
        print(f"Could not fetch wires: {e}")

    # Summary
    print("\n" + "="*60)
    print("ANALYSIS STEPS:")
    print("="*60)
    print("1. Compare the fields from /wires vs /wire/{name}")
    print("2. If /wire/{name} has dimensional data but /wires doesn't:")
    print("   → We need to query each wire individually")
    print("3. Check the PyOpenMagnetics server source code:")
    print("   → Look at the /wires endpoint implementation")
    print("   → See if it accepts query parameters for detailed data")
    print("4. If dimensional data truly doesn't exist in API:")
    print("   → Our name parsing solution was correct")

if __name__ == '__main__':
    main()
