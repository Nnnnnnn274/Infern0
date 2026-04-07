# darksword-kexploit-fun
Building some cool stuff utilizing kernel r/w exploit

## Supposed to be support devices
All iOS/iPadOS 17.0-26.0.1 devices, except A19/M5 devices

## Features
- Escape app sandbox
- Remotely control or force-crash userspace processes
- Arbitrarily overwrite file data on SSV-protected root file systems
- Manipulate UID, GID, and sticky bits for target files
- Disable ASLR by setting `P_DISABLE_ASLR` to `launchd's proc->p_flag`