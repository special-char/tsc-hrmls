FROM frappe/bench:latest

COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh

ENTRYPOINT ["/bin/bash", "/workspace/init.sh"]