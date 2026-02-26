FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Pipeline downloads the artifact as app.jar
COPY app.jar /app/app.jar

EXPOSE 8082
ENTRYPOINT ["java","-jar","/app/app.jar","--server.port=8082"]
