FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Copy the JAR downloaded from JFrog (pipeline saves it as app.jar)
COPY app.jar /app/app.jar

# App listens on 8000 inside container
EXPOSE 8000

# Force Spring Boot to listen on 8000 (avoid host 8080 conflicts)
ENTRYPOINT ["java","-jar","/app/app.jar","--server.port=8000"]
