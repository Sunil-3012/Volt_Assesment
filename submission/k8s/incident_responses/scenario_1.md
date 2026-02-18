1. What’s going wrong?
One of our video processing units has crashed 7 times. It’s stuck in a "CrashLoop," meaning every time it tries to start, it immediately runs out of memory and the system kills it to protect the rest of the cluster.

2. Why did it happen?
We gave the app 512MB of room, but we told the Java engine it could use 384MB just for its "pile of work" (the Heap).

The Math Problem: Java needs extra space for its own "brain" (Metaspace), its "tools" (Thread stacks), and the actual video data it's moving around.

The Breaking Point: When all 8 processing threads tried to grab 50 video chunks at once, the total memory hit roughly 530MB. It hit the "wall" of our 512MB limit, and the kernel killed it instantly.

3. How do we fix it right now?

Double the space: Bump the memory limit to 1GB.

Slow down: Reduce the threads from 8 to 4 so the app doesn't try to do too much at once.

Adjust the Engine: Set the Java Heap to 640MB so there’s plenty of "breathing room" (about 400MB) for the rest of the app's needs.

4. How do we stop this from happening again?
Better Warnings: Set up an alarm that pings us the first time it crashes, not the seventh.

Smart Scaling: We've added a "Horizontal Pod Autoscaler" (HPA). Now, if one pod gets too "full," the system will automatically hire a second "chef" (launch a new pod) to share the load.

Stress Tests: Before we push new code, we'll run a "heavy load" test in our staging area to make sure the "kitchen" is big enough for the job.