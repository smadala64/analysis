You are doing a security review of this member-services chatbot codebase (multi-agent LLM chatbot that calls MCP tools / backend APIs such as enrollment, benefits, claims).

CONCERN: The backend APIs are called with a client-credentials JWT, which only authenticates the application — not the member. We must confirm the code never relies on the LLM for member identity or authorization. If the LLM hallucinates or is prompt-injected with a different member ID, the system must not return that member's data.

Investigate the following and cite exact file paths, class/function names, and line numbers for every claim. If something does not exist, say so explicitly — do not assume.

1. MEMBER VERIFICATION AT SESSION START
   - Find where the member is verified/authenticated (the member validation step).
   - What is stored after successful verification (member ID, subscriber ID, DOB, etc.) and WHERE: server-side session/state store, signed token, agent thread state, or only in the chat history/prompt?
   - Is the verified member ID injected into the LLM prompt/context? Quote the code.

2. HOW MEMBER ID IS SUPPLIED ON SUBSEQUENT TOOL CALLS
   - List every tool/function/MCP tool exposed to the LLM that returns member-specific data. For each, show its schema/signature and state whether it accepts a memberId (or similar identifier) as an LLM-supplied argument.
   - Find the code path where the LLM's tool-call request is executed (tool dispatcher, function invocation filter/middleware, MCP client). Does it take the member ID from the verified session and inject/override it, or pass through whatever the LLM provided?

3. VALIDATION OF LLM-SUPPLIED MEMBER IDS
   - Search for any check comparing the requested member ID to the session's verified member ID (e.g. requestedId == session.memberId) and what happens on mismatch (reject, log, ignore).
   - How are dependents/family members handled (subscriber viewing spouse/child)? Is that relationship verified against authoritative data (enrollment API), or does it trust the LLM/user message?

4. WHERE ENFORCEMENT LIVES
   - Identify which layer enforces member-level authorization: agent orchestration, tool middleware, MCP server, API gateway/APIM policy, or backend API. Say "none found" if there is none.
   - If an MCP server is involved: how does it know which session/member a call belongs to? Is a session ID or signed member context passed out-of-band (headers, context object) separate from LLM-generated arguments? Show the code.
   - Check whether the JWT / outbound HTTP request carries any member-identifying claim or header, and whether the receiving side validates it.

OUTPUT FORMAT
- A section per point (1–4) with findings and code references.
- A request-flow trace: member verification -> session state -> LLM tool call -> dispatcher/MCP -> backend API, marking where member identity comes from at each hop.
- A risk verdict for each point: SAFE / AT RISK / UNCLEAR, with a one-line reason.
- A list of concrete gaps and recommended fixes (e.g. remove memberId from tool schemas and inject from server-side session; add mismatch check in tool middleware).