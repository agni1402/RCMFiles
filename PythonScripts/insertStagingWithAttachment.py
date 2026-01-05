
from simple_salesforce import Salesforce
import os
import base64
import shutil
import logging
from datetime import datetime, timezone

# =========================================================
# SALESFORCE CONFIG
# =========================================================
SF_USERNAME = 'devansh.garg@mirketa.com.newehrdev'
SF_PASSWORD = 'Sanskar@acoe#123456'
SF_SECURITY_TOKEN = 'uNm1FJ3M3lXMxc0hesMNLsgm'
SF_DOMAIN = 'test'   # remove for prod

# =========================================================
# FILE SYSTEM CONFIG
# =========================================================
BASE_INBOUND_DIR = r'C:/RCMFILES/Inbound'
PROCESSED_ROOT_DIR = r'C:/RCMFILES/Processed'
ERROR_DIR = r'C:/RCMFILES/ErrorFiles'

# =========================================================
# SALESFORCE OBJECT & FIELD API NAMES
# =========================================================
DATA_STAGING_OBJECT = 'Data_Staging__c'

FIELD_EDI_TYPE = 'EDI_Type__c'
FIELD_STATUS = 'Status__c'
FIELD_RECON_STATUS = 'ERA_Reconciled_Status__c'
FIELD_DATE = 'Date__c'

# =========================================================
# LOGGING
# =========================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("edi_ingestion.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# =========================================================
# SALESFORCE CONNECTION
# =========================================================
logger.info("Connecting to Salesforce...")
sf = Salesforce(
    username=SF_USERNAME,
    password=SF_PASSWORD,
    security_token=SF_SECURITY_TOKEN,
    domain=SF_DOMAIN
)
logger.info("Connected to Salesforce")

# =========================================================
# UTILITY FUNCTIONS
# =========================================================
def get_unique_destination_path(dest_dir, file_name):
    """
    Ensures file name uniqueness by appending _1, _2, ...
    EXACT behavior like your old script
    """
    base, ext = os.path.splitext(file_name)
    dest_path = os.path.join(dest_dir, file_name)
    counter = 1

    while os.path.exists(dest_path):
        dest_path = os.path.join(dest_dir, f"{base}_{counter}{ext}")
        counter += 1

    return dest_path


def move_file_safely(src_path, dest_root):
    """
    Moves file into date-based folder
    Renames file if same name exists
    """
    today = datetime.now().strftime('%Y-%m-%d')
    dest_dir = os.path.join(dest_root, today)
    os.makedirs(dest_dir, exist_ok=True)

    file_name = os.path.basename(src_path)
    dest_path = get_unique_destination_path(dest_dir, file_name)

    shutil.move(src_path, dest_path)
    logger.info(f"Moved file → {dest_path}")


# =========================================================
# SALESFORCE OPERATIONS
# =========================================================
def create_data_staging_record(edi_type):
    """
    Creates ONE Data Staging record per file
    """
    payload = {
        FIELD_EDI_TYPE: edi_type,
        FIELD_STATUS: f"{edi_type} Received",
        FIELD_RECON_STATUS: f"Generated file for {edi_type}",
        FIELD_DATE: datetime.now(timezone.utc).isoformat()
    }

    result = sf.Data_Staging__c.create(payload)
    logger.info(f"Data Staging created: {result['id']}")
    return result['id']


def upload_and_attach_file(file_path, parent_id):
    """
    Uploads file as ContentVersion and links it
    """
    file_name = os.path.basename(file_path)

    with open(file_path, 'rb') as f:
        encoded = base64.b64encode(f.read()).decode('utf-8')

    cv = sf.ContentVersion.create({
        'Title': file_name,
        'PathOnClient': file_name,
        'VersionData': encoded
    })

    cv_id = cv['id']
    cv_record = sf.ContentVersion.get(cv_id)
    content_document_id = cv_record['ContentDocumentId']

    sf.ContentDocumentLink.create({
        'ContentDocumentId': content_document_id,
        'LinkedEntityId': parent_id,
        'ShareType': 'V'
    })

    logger.info(f"Attached file: {file_name}")


# =========================================================
# MAIN PROCESSING LOGIC
# =========================================================
def process_all_folders():
    logger.info("===== STARTING EDI INGESTION =====")

    for folder_name in os.listdir(BASE_INBOUND_DIR):
        folder_path = os.path.join(BASE_INBOUND_DIR, folder_name)

        if not os.path.isdir(folder_path):
            continue

        logger.info(f"Processing folder: {folder_name}")

        for file in os.listdir(folder_path):
            file_path = os.path.join(folder_path, file)

            if not os.path.isfile(file_path):
                continue

            try:
                logger.info(f"Processing file: {file}")

                # 1️⃣ Create Data Staging record
                staging_id = create_data_staging_record(folder_name)

                # 2️⃣ Upload and attach file
                upload_and_attach_file(file_path, staging_id)

                # 3️⃣ Move file safely (rename if exists)
                move_file_safely(file_path, PROCESSED_ROOT_DIR)

                logger.info(f"SUCCESS: {file}")

            except Exception as e:
                logger.error(f"FAILED: {file} | {e}")

                # Move to error folder with rename protection
                os.makedirs(ERROR_DIR, exist_ok=True)
                error_dest = get_unique_destination_path(ERROR_DIR, file)
                shutil.move(file_path, error_dest)

                logger.info(f"Moved to Error: {error_dest}")

    logger.info("===== EDI INGESTION COMPLETED =====")

# =============================================
# 
# 
# 
# ============
# ENTRY POINT
# =========================================================
if __name__ == "__main__":
    process_all_folders()
