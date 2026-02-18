1. What’s going wrong?
Our "Inference API" is basically a ghost. The pods are alive and healthy, but the "phone book" (the Kubernetes Service) can't find them. Anyone trying to call the API gets a "Connection timed out" because they are essentially dialing a number that isn't connected to any real phones.

2. Why did it happen?
We have two separate "broken links" in the chain:

The Misplaced Tag (Bug 1): The Service is looking for pods that have two specific tags: app: inference-api AND tier: backend. Our pods only have the first tag. Because the second tag is missing, the Service assumes no pods exist and leaves the "Available Endpoints" list empty.

The Strict Guard (Bug 2): We have a security rule (NetworkPolicy) that acts like a bouncer. It only allows the "API Gateway" to talk to the Inference API. However, the "Web Frontend" is trying to skip the line and call the API directly. The bouncer sees someone who isn't on the guest list and silently ignores them, causing a timeout.

3. How do we fix it right now?
We have to fix both the "phone book" and the "bouncer" rules:

Label the Pods: Add the tier: backend tag to the pods so the Service can finally see them. Once this is done, the Service will have active "endpoints" to send traffic to.

Fix the Calling Path: Either tell the "Web Frontend" it must talk to the "API Gateway" first (the correct way), or update the bouncer's guest list to allow the "Web Frontend" in.

4. How do we stop this from happening again?
Automated Alarms: We’ll set up an alert that pings us immediately if a Service has "Zero Endpoints." We shouldn't have to wait for a user to tell us the connection is timed out.

Double-Check the Map: Before we push code, we'll use a tool (a "Linter") that checks if our Service tags and Pod tags actually match. If they don't, it blocks the update before it even hits production.

Follow the Blueprint: We’ll document our "Traffic Flow." Everyone on the team should know that the Frontend talks to the Gateway, and the Gateway talks to the API. No shortcuts!