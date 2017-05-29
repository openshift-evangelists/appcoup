FROM python:2.7-alpine
ADD ./generator/generator.sh /app/generator.sh
ADD ./echo/echo.sh /app/echo.sh
ADD app.sh /app/app.sh
WORKDIR /app
CMD ["sh", "app.sh"]
