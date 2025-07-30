FROM frappe/bench:latest

COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh
