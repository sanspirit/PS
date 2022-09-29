################################################################################
#######   Module import and installation of required modules if missing  #######
################################################################################
__author__ = 'Kyle Fieldus'

from ctypes import c_void_p
import os
import sys
import getopt
try:
    from azure.identity import DefaultAzureCredential
except ImportError:
    print ("Trying to Install required module: azure-identity")
    os.system('python -m pip install azure-identity')
try:
    from azure.keyvault.secrets import SecretClient
except ImportError:
    print ("Trying to Install required module: azure-keyvault-secrets")
    os.system('python -m pip install azure-keyvault-secrets')

################################################################################

def print_usage():
    # Help message to print for usage guidance
    print("Script Usage:" + "\n[script name]" + "\n-k [keyvault name]" + "\n-a [App config]" + "\n-c [Config Explorer]")

def check_keyvault(kvname):
    # Connect to named Azure KeyVault and iterate over secrets (key and value), store into a dict object
    current_kv_values = {}
    KVUri = f"https://{kvname}.vault.azure.net"
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=KVUri, credential=credential)
    secrets = client.list_properties_of_secrets()
    outputfile = "kv_%s.txt" % kvname

    #Populate a dict object with the name, values from the KV
    try:
        for secret in secrets:
            current_kv_values[secret.name] = client.get_secret(secret.name).value
    except: 
        print ("Error, Unable to reach Keyvault named: %s, if this is the first time running this project the resource likeyly doesn't exist yet." % kvname)
    ## Now lets compare with teh values in Octopus
    octopus_values_for_kv = {}

    for key in current_kv_values:
        octopus_values_for_kv[key] = get_octopusvariable(key)

    ## Comparing the two dictionaries and presenting the Octopus Artifact.
    f = open(outputfile, "w")
    if (len(current_kv_values)) > 0:
        for key in current_kv_values:
            if current_kv_values[key] != octopus_values_for_kv[key]:
                f.write("Prospective change detected in KeyVault named: " + kvname + ".\n")
                f.write("The following entries will be changed during this deployment:\n\n")
                f.write("Secret named: "+ key + "\n")
                f.write("Current value: " + current_kv_values[key] + "\n")
                f.write("Updating value: " + octopus_values_for_kv[key] + "\n")
                f.write("----\n")
    else:
        f.write("Cannot read or locate any secrets for KeyVault named %s \n" % kvname)
        f.write("All new entries will be added with the following values:\n\n")
        for entry in octopus_values_for_kv:
            f.write("Key: " + entry + "\n")
            f.write("Value: " + octopus_values_for_kv[entry] + "\n")
            f.write("----\n")
        print("Cannot read or locate any secrets for KeyVault named %s" % kvname)
    f.close()
    createartifact(outputfile)

if __name__ == "__main__":
    try:
        opts, args = getopt.getopt(sys.argv[1:], "k:a:c:", ["keyvault=", "appconfig=", "configexplorer="])
    except getopt.GetoptError as err:
        print (err)
        print_usage()
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-k':
            print ("Keyvault comparison will happen on keyvault named: %s" % arg)
            check_keyvault(arg)
        elif opt == '-a':
            print ("App Config comparison will happen on: %s" % arg)
            check_app_config(arg)
        elif opt == '-c':
            print ("Config Explorer comparison will happen on keyvault named: %s" % arg)
            check_config_explorer(arg)
        else:
            print_usage()
