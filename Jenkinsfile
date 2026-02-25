pipeline {
  agent any

  tools {
    // Configure these tool names in Jenkins Global Tool Configuration
    jdk 'jdk17'          // change if your Jenkins uses jdk11/jdk8
    maven 'maven3'
  }

  environment {
    // ---- EDIT THESE ----
    REPO_URL        = 'https://github.com/Akash0902/Boardgame.git'
    BRANCH          = 'main'

    APP_NAME        = 'boardgame'
    DOCKER_IMAGE    = 'YOUR_DOCKERHUB_OR_ECR_REPO/boardgame'   // e.g. dockerhubuser/boardgame OR <acct>.dkr.ecr.<region>.amazonaws.com/boardgame
    DOCKER_TAG      = "${BUILD_NUMBER}"

    // SonarQube (optional)
    SONARQUBE_ENV   = 'sonar-server'  // Jenkins "Configure System" -> SonarQube servers name
    SONAR_PROJECT_KEY  = 'Boardgame'
    SONAR_PROJECT_NAME = 'Boardgame'

    // K8s deploy
    K8S_NAMESPACE   = 'webapps'
    K8S_MANIFEST    = 'deployment-service.yaml'

    // Credentials IDs (create in Jenkins Credentials)
    DOCKER_CRED_ID  = 'docker-cred'   // DockerHub creds OR ECR creds if using docker login
    // If using ECR login via AWS CLI, use AWS creds or instance role instead of docker creds
    // AWS_CRED_ID  = 'aws-cred'
    KUBECONFIG_CRED = 'k8s-cred'      // Jenkins Kubernetes credentials (kubeconfig)
  }

  stages {

    stage('Checkout') {
      steps {
        git branch: "${BRANCH}", url: "${REPO_URL}"
      }
    }

    stage('Build + Unit Tests') {
      steps {
        sh 'mvn -B clean test'
      }
    }

    stage('Package') {
      steps {
        sh 'mvn -B -DskipTests package'
        sh 'ls -al target || true'
      }
    }

    stage('SonarQube Analysis (optional)') {
      when { expression { return env.SONARQUBE_ENV?.trim() } }
      steps {
        withSonarQubeEnv("${SONARQUBE_ENV}") {
          sh """
            mvn -B sonar:sonar \
              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
              -Dsonar.projectName=${SONAR_PROJECT_NAME} \
              -Dsonar.java.binaries=target
          """
        }
      }
    }

    stage('Quality Gate (optional)') {
      when { expression { return env.SONARQUBE_ENV?.trim() } }
      steps {
        // Requires "Quality Gates" + SonarQube plugin configured
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
      }
    }

    stage('Push Docker Image') {
      steps {
        script {
          withDockerRegistry(credentialsId: "${DOCKER_CRED_ID}") {
            sh "docker push ${DOCKER_IMAGE}:${DOCKER_TAG}"
          }
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        // Replace image tag dynamically in manifest before applying
        sh """
          sed -i 's|IMAGE_PLACEHOLDER|${DOCKER_IMAGE}:${DOCKER_TAG}|g' ${K8S_MANIFEST}
          cat ${K8S_MANIFEST}
        """

        withKubeConfig(credentialsId: "${KUBECONFIG_CRED}", namespace: "${K8S_NAMESPACE}") {
          sh "kubectl apply -f ${K8S_MANIFEST}"
          sh "kubectl get pods -n ${K8S_NAMESPACE}"
          sh "kubectl get svc  -n ${K8S_NAMESPACE}"
        }
      }
    }
  }

  post {
    always {
      sh 'docker system prune -af || true'
    }
  }
}
