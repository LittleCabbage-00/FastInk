FastInk Markdown diagram renderer

Bundled third-party engine: Mermaid 12.2.0 (MIT).
Source: https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz
Published package integrity:
sha512-w7nr/SFrLO7BaVTs3dQTvYSV6nYSBj0Yy9DjBhsIJtAcHqRzXSq4Pg32ujHZ/AdWsAMNEvvhbm5dt9E2tOiHzw==

mermaid.min.js is the upstream prebuilt browser bundle. Its license comments
and the separate MERMAID-LICENSE.txt are preserved. No SoloMD code is included.

render_diagram.ps1 uses an existing Edge/Chrome installation in headless mode,
with a private temporary browser profile and a resource-limited process job.
ResourceJob.cs is FastInk's own process guard, shared with its safe build tools.
It limits the new process tree to 640 MB and 25 percent CPU, and closes only
that process tree. Existing browser windows and profiles are not used.

Diagram pages use a local script, strict Mermaid security, and a restrictive
content security policy that does not allow external network resources.
