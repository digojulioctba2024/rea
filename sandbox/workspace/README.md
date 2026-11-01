# Sandbox workspace

This directory is the only host folder the offline `lab` container can see.

```
workspace/
  samples/   target files (read-only inside the container, mounted at /samples)
  out/       results, evidence and captures (writable, mounted at /out)
```

Put binaries, APKs, ASARs, firmware dumps or extracted app directories in
`samples/`. Anything the lab writes must go to `out/` (the container root
filesystem is read-only).

These files are ignored by Git. Do not commit samples or analysis output.
