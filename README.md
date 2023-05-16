## Self Sign CA Infrastructure Auto Setup & Management Script
### Create & operate a full CA infrastructure from scratch ( root CA + intermediate CA ) 
#### Script provides menu driven support for: 
   * Creation of a base CA infrastructure with centralised certificate policy controls
   * Simplified Server or User type certificate creation through pre-built keyUsage/extendedKeyUsage policy
   * Certificate Revocation List (CRL) creation and ongoing management
   * Online Certificate Status Protocol (OSCP) setup and management 
   * Certificate revocation support via CRL or OSCP 
 
  #### Prerequisites: OpenSSL + any Linux flavour with a bash shell (or WSL)
  
  #### Notes: 
 * Set script default to either RSA & Elliptical Curve prior to starting
 * Script is fully functional with RSA, EC is experimental
 * To do: 
    *  Complete the implementation of Elliptic Curve options
    *  Extend script support for certificate provisioning via 3rd party certificate signing requests

