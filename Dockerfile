FROM "circleci/circleci-cli:latest"
COPY "bump-orbs.sh" "/bump-orbs.sh"
ENTRYPOINT ["/bump-orbs.sh"]