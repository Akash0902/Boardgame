pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  tools {
    jdk 'jdk17'
    maven 'Maven3'
  }

  environment {
    // ----------------------
    // Source
    // ----------------------
    REPO_URL = 'https://github.com/Akash0902/Boardgame.git'
    BRANCH   = 'main'

    // ----------------------
    // JFrog (Artifactory)
    // ----------------------
    JFROG_BASE_URL = 'http://13.200.239.127:8081/artifactory'
    JFROG_REPO_KEY = 'boardgame'
    JFROG_CRED_ID  = 'jfrog'

    // ----------------------
    // SonarQube
    // ----------------------
    SONARQUBE_ENV      = 'sonar'
    SONAR_PROJECT_KEY  = 'boardgame'
    SONAR_PROJECT_NAME = 'boardgame'

    // ----------------------
    // Email
    // ----------------------
    EMAIL_TO = 'akashadak0012@gmail.com'

    // ----------------------
    // Artifact coordinates in JFrog (DOWNLOAD)
    // ----------------------
    GROUP_PATH  = 'com/javaproject'
    ARTIFACT_ID = 'database_service_project'
    VERSION     = '0.0.5-SNAPSHOT'
    PACKAGING   = 'jar'

    // ----------------------
    // Docker / ECR Public
    // ----------------------
    IMAGE_NAME = 'boardgame-app'
    IMAGE_TAG  = "${BUILD_NUMBER}"

    AWS_REGION_ECR_PUBLIC = 'us-east-1'
    ECR_PUBLIC_REGISTRY   = 'public.ecr.aws/k6c3y2y2'
    IMAGE_REPO            = 'public.ecr.aws/k6c3y2y2/boardgame'

    // ----------------------
    // Kubernetes / EKS
    // ----------------------
    K8S_MANIFEST = 'deployment.yml'

    // IMPORTANT: set these to your cluster
    EKS_CLUSTER_NAME = 'boardgame'
    EKS_REGION       = 'ap-south-1'

    // If your deployment metadata.name is different, change it
    K8S_DEPLOYMENT_NAME = 'boardgame-deployment'
  }

  stages {

    stage('Checkout') {
      steps {
        git branch: "${BRANCH}", url: "${REPO_URL}"
        sh 'ls -al'
        sh 'test -f ${K8S_MANIFEST}'
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
        archiveArtifacts artifacts: 'target/**/*.*', fingerprint: true, onlyIfSuccessful: true
      }
    }

    stage('SonarQube Analysis') {
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

    stage('Quality Gate') {
      when { expression { return env.SONARQUBE_ENV?.trim() } }
      steps {
        script {
          timeout(time: 10, unit: 'MINUTES') {
            def qg = waitForQualityGate()
            if (qg.status != 'OK') {
              emailext(
                to: "${EMAIL_TO}",
                subject: "❌ QUALITY GATE FAILED | ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                attachLog: true,
                body: """
                  <h3 style="color:#d93025;">Quality Gate Failed</h3>
                  <p><b>Status:</b> ${qg.status}</p>
                  <p><b>Build URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
                """
              )
              error "Pipeline aborted due to Quality Gate failure: ${qg.status}"
            }
          }
        }
      }
    }

    stage('Deploy Artifact to JFrog (boardgame repo)') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: "${JFROG_CRED_ID}",
          usernameVariable: 'JF_USER',
          passwordVariable: 'JF_PASS'
        )]) {
          script {
            // IMPORTANT: real XML (not &lt; &gt;)
            writeFile file: 'settings.xml', text: """
<settings>
  <servers>
    <server>
      <id>${JFROG_REPO_KEY}</id>
      <username>${env.JF_USER}</username>
      <password>${env.JF_PASS}</password>
    </server>
  </servers>
</settings>
""".trim()

            sh 'mvn -B -DskipTests deploy --settings settings.xml'
          }
        }
      }
    }

    stage('Fetch Artifact from JFrog (for Docker)') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: "${JFROG_CRED_ID}",
          usernameVariable: 'JF_USER',
          passwordVariable: 'JF_PASS'
        )]) {
          sh '''
            set -e

            BASE="${JFROG_BASE_URL}/${JFROG_REPO_KEY}/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}"
            echo "JFrog base: $BASE"

            if echo "${VERSION}" | grep -q "SNAPSHOT$"; then
              echo "Snapshot detected -> downloading maven-metadata.xml"
              curl -fL -u "$JF_USER:$JF_PASS" "$BASE/maven-metadata.xml" -o maven-metadata.xml

              # Try to extract first <value> that belongs to our extension
              SNAP_VALUE=$(awk '
                BEGIN {ext="'"${PACKAGING}"'"; inSV=0; inExt=0;}
                /<snapshotVersion>/ {inSV=1}
                inSV && /<extension>/ {
                  gsub(/.*<extension>|<\\/extension>.*/,"");
                  if ($0==ext) inExt=1; else inExt=0
                }
                inSV && inExt && /<value>/ {
                  gsub(/.*<value>|<\\/value>.*/,"");
                  print; exit
                }
                /<\\/snapshotVersion>/ {inSV=0; inExt=0}
              ' maven-metadata.xml)

              [ -n "$SNAP_VALUE" ] || (echo "Snapshot parse failed" && exit 1)

              FILE="${ARTIFACT_ID}-${SNAP_VALUE}.${PACKAGING}"
              URL="${BASE}/${FILE}"
            else
              FILE="${ARTIFACT_ID}-${VERSION}.${PACKAGING}"
              URL="${BASE}/${FILE}"
            fi

            echo "Downloading: $URL"
            curl -fL -u "$JF_USER:$JF_PASS" "$URL" -o app.jar
            ls -lh app.jar
          '''
        }

        archiveArtifacts artifacts: 'app.jar', fingerprint: true
      }
    }

    stage('Build Docker Image') {
      steps {
        sh '''
          set -e
          test -f Dockerfile
          test -f app.jar
          docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
        '''
      }
    }

    stage('Push Docker Image to ECR (version + latest)') {
      steps {
        sh '''
          set -e

          # ECR Public login (AWS recommends us-east-1 for public registry auth)
          aws ecr-public get-login-password --region ${AWS_REGION_ECR_PUBLIC} | \
            docker login --username AWS --password-stdin ${ECR_PUBLIC_REGISTRY}

          docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_REPO}:${IMAGE_TAG}
          docker push ${IMAGE_REPO}:${IMAGE_TAG}

          docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_REPO}:latest
          docker push ${IMAGE_REPO}:latest
        '''
      }
    }

    stage('Deploy to Kubernetes (EKS)') {
      steps {
        sh '''
          set -e
          test -f ${K8S_MANIFEST}

          echo "AWS identity:"
          aws sts get-caller-identity || true

          echo "Configuring kubectl for EKS (refresh every run)..."
          aws eks update-kubeconfig --region ${EKS_REGION} --name ${EKS_CLUSTER_NAME}

          kubectl config current-context
          kubectl get nodes

          # Render manifest with the exact pushed image tag
          cp ${K8S_MANIFEST} ${K8S_MANIFEST}.rendered
          sed -i "s|IMAGE_PLACEHOLDER|${IMAGE_REPO}:${IMAGE_TAG}|g" ${K8S_MANIFEST}.rendered

          echo "----- Rendered Manifest -----"
          cat ${K8S_MANIFEST}.rendered

          kubectl apply -f ${K8S_MANIFEST}.rendered

          # rollout status (same deployment pattern you’ve used before)
          kubectl rollout status deployment/${K8S_DEPLOYMENT_NAME} --timeout=2m

          kubectl get pods -o wide
          kubectl get svc
        '''
      }
    }
  }

  post {
    success {
      emailext(
        to: "${EMAIL_TO}",
        subject: "✅ SUCCESS | ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        mimeType: 'text/html',
        body: """
          <h3 style="color:#188038;">Pipeline Succeeded</h3>
          <p><b>Job:</b> ${env.JOB_NAME}</p>
          <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
          <p><b>Build URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
          <p><b>Image pushed:</b> ${IMAGE_REPO}:${IMAGE_TAG} and ${IMAGE_REPO}:latest</p>
        """
      )
    }

    failure {
      emailext(
        to: "${EMAIL_TO}",
        subject: "❌ FAILED | ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        mimeType: 'text/html',
        attachLog: true,
        body: """
          <h3 style="color:#d93025;">Pipeline Failed</h3>
          <p><b>Job:</b> ${env.JOB_NAME}</p>
          <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
          <p><b>Build URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
          <p>Please check attached console log for details.</p>
        """
      )
    }

    always {
      sh 'rm -f settings.xml app.jar maven-metadata.xml deployment.yml.rendered || true'
    }
  }
}
