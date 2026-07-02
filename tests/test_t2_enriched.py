#!/usr/bin/env python3
"""Test T2: Validate enriched MRU entry structure."""

import socket, json, sys

def test_enriched_entries(socket_path):
    """Connect to daemon, send get_mru, validate enriched entry structure."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    
    try:
        sock.connect(socket_path)
        sock.sendall(b'{"type":"get_mru"}\n')
        
        response = b''
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
        sock.close()
        
        data = json.loads(response.decode().strip())
        
        errors = []
        
        if "mru" not in data:
            errors.append("Missing 'mru' field")
            
        if "current" not in data:
            errors.append("Missing 'current' field")
            
        if "selected" not in data:
            errors.append("Missing 'selected' field")
            
        if len(data.get("mru", [])) < 2:
            errors.append(f"Expected >= 2 MRU entries, got {len(data.get('mru', []))}")
            
        for i, entry in enumerate(data.get("mru", [])):
            if "id" not in entry:
                errors.append(f"Entry {i} missing 'id'")
            if "running" not in entry:
                errors.append(f"Entry {i} missing 'running'")
            if "name" not in entry:
                errors.append(f"Entry {i} missing 'name'")
            if "icon" not in entry:
                errors.append(f"Entry {i} missing 'icon'")
            if "exec" not in entry:
                errors.append(f"Entry {i} missing 'exec'")
                
        if errors:
            print("FAILED:")
            for e in errors:
                print(f"  - {e}")
            sys.exit(1)
        else:
            print(f"PASS: {len(data['mru'])} entries, all have [id, running, name, icon, exec]")
            sys.exit(0)
            
    except Exception as e:
        print(f"FAILED: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: test_t2_enriched.py <socket_path>")
        sys.exit(1)
    test_enriched_entries(sys.argv[1])
