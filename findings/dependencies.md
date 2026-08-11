# Vulnerable dependencies

| Severity | Component | Version | Identifiers | File |
|---|---|---|---|---|
| LOW | jquery | 1.8.3 | 162 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |
| MEDIUM | jquery | 1.8.3 | 11974 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |
| MEDIUM | jquery | 1.8.3 | CVE-2012-6708 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |
| MEDIUM | jquery | 1.8.3 | CVE-2015-9251 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |
| MEDIUM | jquery | 1.8.3 | CVE-2019-11358 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |
| MEDIUM | jquery | 1.8.3 | CVE-2020-11023 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |
| MEDIUM | jquery | 1.8.3 | CVE-2020-7656 | `/home/user/webbin-sandbox/mirror-raw/localhost:8080/assets/jquery-1.8.3.min.js` |


## Confidence note

retire.js fingerprints known library files by filename and version banner.
Recall against webpacked or rolled-up vendor chunks is weak: a bundled copy
of a vulnerable library frequently carries neither. Treat this as a floor,
not a ceiling -- a clean result here is not evidence of a clean dependency
posture. Passive audit has no lockfile, so proper SCA needs the build repo.
