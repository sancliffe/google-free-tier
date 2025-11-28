apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-gke-deployment
spec:
  # WARNING: While the GKE Autopilot *Management Fee* is waived for one cluster, 
  # the compute resources (vCPU/RAM) defined below ARE BILLED.
  # GKE Autopilot is NOT part of the "Always Free" Compute Engine tier.
  replicas: 1 
  selector:
    matchLabels:
      app: hello-gke
  template:
    metadata:
      labels:
        app: hello-gke
    spec:
      # --- Security Hardening ---
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000 # 'node' user UID
        runAsGroup: 1000
        fsGroup: 1000

      containers:
      - name: hello-gke-container
        image: ${image}
        ports:
        - containerPort: 8080
      
        # Inject Environment Variables
        env:
        - name: GOOGLE_CLOUD_PROJECT
          value: "${project_id}"
        - name: ASSETS_URL
          value: "${assets_url}"

        # --- GKE Autopilot Resource Requirements ---
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"

        # --- Health Probes ---
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
          
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10