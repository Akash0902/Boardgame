pipeline {
  agent any

  tools {
    jdk 'jdk17'
    maven 'maven3'
  }

  environment {
    // ---- EDIT THESE ----
    REPO_URL        = 'https://github.com/Akash0902/Boardgame.git'
    BRANCH          = 'main'

    APP_NAME        = 'boardgame'
    DOCKER_IMAGE    = 'YOUR_DOCKERHUB_OR_ECR_REPO/boardgame'   // change this
    DOCKER_TAG      = "${BUILD_NUMBER}"

    // SonarQube
    SONARQUBE_ENV      = 'sonar-server'   // Jenkins -> Configure System -> SonarQube servers name
    SONAR_PROJECT_KEY  = 'Boardgame'
    SONAR_PROJECT_NAME = 'Boardgame'

    // K8s deploy
    K8S_NAMESPACE   = 'webapps'
    K8S_MANIFEST    = 'deployment-service.yaml'

    // Credentials IDs
    DOCKER_CRED_ID  = 'docker-cred'
    KUBECONFIG_CRED = 'k8s-cred'

    // Email
    EMAIL_TO        = 'akashadak0012@gmail.com'
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

    stage('SonarQube Analysis') {
      when { expression { return env.SONARQUBE_ENV?.trim() } }
      steps {
        // withSonarQubeEnv is required so Jenkins can track the analysis task for waitForQualityGate [3](https://github.com/MKdevops-ai/BoardGame/blob/main/deployment-service.yaml)[4](https://github.com/Melystial/Brookhaven-script/blob/main/brookhaven)
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

    stage('Quality Gate') {
      when { expression { return env.SONARQUBE_ENV?.trim() } }
      steps {
        // waitForQualityGate waits for SonarQube result (requires webhook configured) [3](https://github.com/MKdevops-ai/BoardGame/blob/main/deployment-service.yaml)[4](https://github.com/Melystial/Brookhaven-script/blob/main/brookhaven)
        timeout(time: 10, unit: 'MINUTES') {
          script {
            def qg = waitForQualityGate()  // returns status like OK / ERROR
            if (qg.status != 'OK') {

              // Email immediately when Quality Gate fails [1](https://www.coursera.org/learn/implementing-cicd-with-jenkins-creating-pipeline-as-code)
              emailext(
                to: "${EMAIL_TO}",
                subject: "❌ QUALITY GATE FAILED | ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                attachLog: true,
                body: """
                  <h3 style="color:#d93025;">Quality Gate Failed</h3>
                  <p><b>Status:</b> ${qg.status}</p>
                  <p><b>Job:</b> ${env.JOB_NAME}</p>
                  <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
                  <p><b>Build URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
                  <p><b>Action:</b> Pipeline stopped before Docker/JFrog/K8s steps.</p>
                  <hr/>
                  <p>Tip: Fix Sonar issues and re-run. (Console log attached)</p>
                """
              )

              // Stop pipeline here (as required)
              error "Pipeline aborted due to Quality Gate failure: ${qg.status}"
            }
          }
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
        // Safer: create a temp manifest so we don't permanently modify your repo file in workspace
        sh """
          cp ${K8S_MANIFEST} ${K8S_MANIFEST}.rendered
          sed -i 's|IMAGE_PLACEHOLDER|${DOCKER_IMAGE}:${DOCKER_TAG}|g' ${K8S_MANIFEST}.rendered
          echo "----- Rendered Manifest -----"
          cat ${K8S_MANIFEST}.rendered
        """

        withKubeConfig(credentialsId: "${KUBECONFIG_CRED}", namespace: "${K8S_NAMESPACE}") {
          sh "kubectl apply -f ${K8S_MANIFEST}.rendered"
          sh "kubectl get pods -n ${K8S_NAMESPACE}"
          sh "kubectl get svc  -n ${K8S_NAMESPACE}"
        }
      }
    }
  }

  post {
    success {
      // Success mail [1](https://www.coursera.org/learn/implementing-cicd-with-jenkins-creating-pipeline-as-code)
      emailext(
        to: "${EMAIL_TO}",
        subject: "✅ PIPELINE SUCCESS | ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        mimeType: 'text/html',
        attachLog: true,
        body: """
          <h3 style="color:#188038;">Pipeline Successful</h3>
          <p><b>Job:</b> ${env.JOB_NAME}</p>
          <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
          <p><b>Build URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
          <p><b>Result:</b> ✅ Build → Sonar → Docker → Push → Deploy completed successfully.</p>
          <hr/>
          <p>Console log attached for reference.</p>
        """
      )
    }

    failure {
      // General failure mail (covers failures outside Quality Gate too) [1](https://www.coursera.org/learn/implementing-cicd-with-jenkins-creating-pipeline-as-code)
      emailext(
        to: "${EMAIL_TO}",
        subject: "❌ PIPELINE FAILED | ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        mimeType: 'text/html',
        attachLog: true,
        body: """
          <h3 style="color:#d93025;">Pipeline Failed</h3>
          <p><b>Job:</b> ${env.JOB_NAME}</p>
          <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
          <p><b>Build URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
          <p><b>Result:</b> ❌ Check the console log (attached) to identify the failing stage.</p>
        """
      )
    }

    always {
      sh 'docker system prune -af || true'
      sh 'rm -f deployment-service.yaml.rendered || true'
    }
  }
}
