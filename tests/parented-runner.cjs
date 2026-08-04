"use strict";
const artifact = require(process.argv[2]);
const app = artifact.Elm.ParentedMain.init();
app.ports.report.subscribe((value) => {
  if (process.send) process.send({ report: value });
  if (value === "finished") setTimeout(() => process.exit(0), 10);
});
