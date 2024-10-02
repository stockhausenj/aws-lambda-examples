FROM public.ecr.aws/lambda/python:3.11

WORKDIR /var/task

RUN pip install psycopg2-binary -t .

COPY . .

RUN pip install -r requirements.txt


CMD ["app.handler"]
