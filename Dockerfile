FROM myoung34/github-runner:2.333.1

COPY entrypoint.sh /runner-entrypoint.sh
RUN chmod +x /runner-entrypoint.sh

ENTRYPOINT ["/runner-entrypoint.sh"]
