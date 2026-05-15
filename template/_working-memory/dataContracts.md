# Data Contracts

<!-- Canonical shapes for data flowing through the application. -->
<!-- Agents must consume data through these contracts. -->
<!-- When mocking data, conform to these shapes exactly. -->

<!-- Three valid formats — pick whichever survives drift best:               -->
<!--   1. POINTER. Link to the source-of-truth file(s). Best for typed       -->
<!--      projects where the code IS the contract — TypeScript interfaces,   -->
<!--      Pydantic models, Zod schemas. Duplicating types here just creates  -->
<!--      drift.                                                              -->
<!--   2. SCHEMA SKETCH. Paste a JSON-schema / OpenAPI / GraphQL excerpt.    -->
<!--      Best for API surfaces defined outside the code.                    -->
<!--   3. PROSE. Describe the shape in human-readable form. Best for         -->
<!--      boundaries the code doesn't enforce — file formats, message       -->
<!--      payloads from external systems, naming conventions.                -->
<!-- Mix and match per contract; not every contract needs the same format.  -->

_No contracts defined yet._
