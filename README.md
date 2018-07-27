# SUSE and Microsoft Solution templates for SAP Applications

## Overview
This repository provides several predefined solution templates for SAP Applications from SUSE and Microsoft for simplified deployment on Microsoft Azure

With the help of the Azure Resource Manager (ARM) we can simpify the deployment of the needed infrastructure for SAP Applications on Microsoft Azure
Such ARM templates are JSON files that define the infrastructure and configuration of a solution on Azure and by using such templates, you can speed up the deployment and deploy the resources in a consistend state.

## Solution
Such templates can get complex for a infrastructure like SAP Applications, therefore we created a SUSE offering directly in the [Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/suse.suse-sap-infra?tab=Overview)

The solution templates are designed to simplify and automate the creation of the required infrastructure for deploying SAP Netweaver
and SAP HANA on SUSE Linux Enterprise Server for SAP Applications premium images in Azure and create
* Several virtual machines
* Virtual network and subnet
* Several disks depending on the solution sizes
* Availability Sets and load balancer if High-Availablity (HA) is selected

We provide within this repository the sources of the marketplace solution templates in order to provide
* the possibility to use them with your deploy infrasturcture instead of using the Azure Portal
* a way to work in the public on new features
* collaborate on your real world requirements

## Documentation
The documentation of some details of the templates could be found at our public documentation of [SUSE Best Practices](https://www.suse.com/documentation/suse-best-practices/sbp-sap-msazure-solution-templates/data/sbp-sap-msazure-solution-templates.html)

## Azure articles
To learn more about the format of the template and how you construct it, see
[Create your first Azure Resource Manager template](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-create-first-template).
To view the JSON syntax for resources types, see [Define resources in Azure Resource Manager templates](https://docs.microsoft.com/en-us/azure/templates/).

## Future Development ideas
* on the HA setup deploy the pacemaker infrastructure
* add Azure files for uploading SAP media
* install SAP HANA directly from the workflow if SAP media are present

## Directory structure
### Overall structure

xTier                        - the solution templates

docu                         - documentation of some backgrounds

for_marketplace              - temporary for creating Azure Marketplace offering

scripts                      - Scripts used in the templates for setup the infrastructure

tool                         - some helper tools


### Details for the 2Tier template as example:

 azuredeploy.json            - Template which creates the resources

 azuredeploy.parameter.json  - Parameterfile for github deployment

 metadata.json               - Description for github deployment


 version.txt                 - Version number of the template

 createUiDefinition.json     - Frontend for the Marketplace

 mp_guid.txt                 - Unique Id for Marketplace

 mainTemplate.json           - Temporary copy for the Marketplace

## Contribution
If you would like to contribute, please fork this repository and *send pull requests*.

>**NOTE**
>
>**Please do not make any commits to the `master` branch** as `master` is reserved for releases only.
>
> **Always commit to `develop`**

Have a lot of fun...
