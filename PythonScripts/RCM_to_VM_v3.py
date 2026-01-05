import os
import requests
from simple_salesforce import Salesforce
from base64 import b64decode

# sf = Salesforce(
#     username='ghanshyam.bhatt@mirketa.com.ehrdev',        # Your Salesforce login email
#     password='Mirketa@7654321',       # Your Salesforce password
#     security_token='1kwq1qfGdsagDvH6MH9ZXICi',    # Your security token (get from Salesforce)
#     domain='test'  # use 'test' for sandbox
# )

sf = Salesforce(
    username='devansh.garg@mirketa.com.newehrdev',        # Salesforce login username
    password='Sanskar@acoe#123456',       # Salesforce password
    security_token='uNm1FJ3M3lXMxc0hesMNLsgm',    # security token (get from Salesforce)
    domain='test'  # using 'test' for sandbox
)
 
# === Output folders ===
# base_dir = r"C:\ACOE\Dataloader\DataSetupFiles"
# base_dir = r"C:/RCMFiles/Python/Dataloader/Fetched Files from RCM/"
base_dir = r"C:/RCMFILES/Outbound/"
download_success = True

# for f in folders.values():
#     os.makedirs(os.path.join(base_dir, f), exist_ok=True)
 
# === Fetch Data Setup Records with File Links ===
query = """
SELECT Id, EDI_Type__c, (SELECT ContentDocumentId FROM ContentDocumentLinks)
FROM Data_Staging__c
WHERE Id != null and Status__c in ('270 EDI Generated', '837I EDI Generated', '837P EDI Generated')
"""
records = sf.query_all(query)['records']
 
# === Track successfully processed record IDs ===
exported_records = []
 
# === Process each Data Setup record ===
for rec in records:
    record_id = rec['Id']
    edi_type = rec.get('EDI_Type__c')  # Get the EDI type from the record
    print(f"Processing record ID: {record_id}, EDI Type: {edi_type}")

    # Safe handling of ContentDocumentLinks
    content_doc_links = rec.get('ContentDocumentLinks')
    links = content_doc_links.get('records', []) if content_doc_links else []
    
    print(f"Processing record ID: {record_id}, EDI Type: {edi_type}")
    
    # Skip conditions
    if not edi_type:
        print(f"Skipping record ID {record_id} - No EDI Type specified")
        continue
    if not links:
        print(f"Skipping record ID {record_id} - No files attached")
        continue

    # Skip this record if edi_type is None or empty
    # if not edi_type or not links:
    #     reason = "No EDI Type specified" if not edi_type else "No files attached"
    #     print(f"Skipping record ID {record_id} - {reason}")
    #     continue
    # links = rec.get('ContentDocumentLinks', {}).get('records', [])
    # download_success = True
    

    # Create folder for this EDI type if it doesn't exist
    if(edi_type == "270 EDI"):
        end_folder = "270 EDI"
    elif(edi_type == "837I EDI"):
        end_folder = "837I EDI"
    elif(edi_type == "837P EDI"):
        end_folder = "837P EDI"
    else:
        continue
    
    edi_folder = os.path.join(base_dir, end_folder)
    os.makedirs(edi_folder, exist_ok=True)

    for link in links:
        try:
            doc_id = link['ContentDocumentId']
            doc = sf.ContentDocument.get(doc_id)
            version_id = doc['LatestPublishedVersionId']
            version = sf.ContentVersion.get(version_id)

            file_title = version['Title']
            file_ext = version['FileExtension']

            # Download the file content
            download_url = f"{sf.base_url}sobjects/ContentVersion/{version_id}/VersionData"
            headers = {'Authorization': 'Bearer ' + sf.session_id}
            response = requests.get(download_url, headers=headers)

            if response.status_code == 200:
                # Save to EDI type folder
                local_path = os.path.join(edi_folder, f"{file_title}.{file_ext}")
                with open(local_path, 'wb') as f:
                    f.write(response.content)
                print(f"Downloaded: {file_title} → {local_path}")
            else:
                print(f"Failed to download: {file_title}")
                download_success = False

        except Exception as e:
            print(f"Error processing document: {e}")
            download_success = False

    if download_success:
        exported_records.append({'Id': record_id, 'Status__c': 'Exported'})
 
# === Perform bulk update after all downloads ===
if exported_records:
    try:
        result = sf.bulk.Data_Staging__c.update(exported_records, batch_size=200, use_serial=True)
        print("Bulk update successful for the following records:")
        for res in result:
            print(res)
    except Exception as e:
        print(f"Bulk update failed: {e}")
else:
    print("No records were eligible for status update.")