apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-gke-deployment
spec:
  replicas: 2 # Run two instances of our application
  selector:
    matchLabels:
      app: hello-gke
  template:
    metadata:
      labels:
        app: hello-gke
    spec:
      containers:
      - name: hello-gke-container
        image: ${image}
        ports:
        - containerPort: 8080
        
        # --- GKE Autopilot Resource Requirements ---
        # Explicit requests are required for Autopilot to calculate billing 
        # and allocate the correct class of compute resources.
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"

        # --- Health Probes ---
        # Liveness: Restarts the container if it freezes or deadlocks.
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
          
        # Readiness: Don't send traffic until this passes (e.g., during startup).
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10