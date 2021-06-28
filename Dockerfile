FROM openjdk:11

ARG WAR_FILE=./target/*.jar

COPY ${WAR_FILE} webapp.war

CMD ["java", "-Dspring.profiles.active=docker", "-jar", "webapp.war"]