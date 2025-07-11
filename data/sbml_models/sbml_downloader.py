import requests
import time
import os

def download_sbml_model(bigg_id, output_dir, model_format='xml'):
    """
    BiGG Models'tan belirli bir BiGG ID'ye sahip SBML modelini indirir.
    İndirilen .xml dosyasını .sbml olarak yeniden adlandırır.
    """
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # BiGG Models API'si genellikle .xml uzantısını kullanır
    download_url = f"http://bigg.ucsd.edu/static/models/{bigg_id}.{model_format}"
    
    # İndirilecek dosyanın geçici adı (API'den gelen uzantı ile)
    temp_filename = os.path.join(output_dir, f"{bigg_id}.{model_format}")
    # Nextflow'un beklediği nihai dosya adı
    final_filename = os.path.join(output_dir, f"{bigg_id}.sbml")

    print(f"Attempting to download {bigg_id} from: {download_url}")
    try:
        response = requests.get(download_url, stream=True)
        response.raise_for_status() # HTTP hataları için istisna fırlatır

        with open(temp_filename, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        print(f"Successfully downloaded {temp_filename}")

        # İndirilen .xml dosyasını .sbml olarak yeniden adlandır
        os.rename(temp_filename, final_filename)
        print(f"Renamed {temp_filename} to {final_filename}")
        return True

    except requests.exceptions.RequestException as e:
        print(f"ERROR: Could not download {bigg_id} from {download_url}. Error: {e}")
        # Hata durumunda geçici dosyayı sil (eğer oluşturulduysa)
        if os.path.exists(temp_filename):
            os.remove(temp_filename)
        return False
    except OSError as e:
        print(f"ERROR: Could not rename {temp_filename} to {final_filename}. Error: {e}")
        return False

def main():
    bigg_id_list_file = "bigg_id_list.txt"
    output_directory = "data/sbml_models"
    delay_between_requests = 0.15 # Saniyede 10 isteği aşmamak için (1/10 = 0.1)

    # bigg_id_list.txt dosyasının varlığını kontrol et
    if not os.path.exists(bigg_id_list_file):
        print(f"ERROR: '{bigg_id_list_file}' not found in the current directory.")
        print("Please ensure 'bigg_id_list.txt' is in the same directory as this script.")
        return

    # bigg_id_list.txt dosyasından ID'leri oku
    with open(bigg_id_list_file, 'r') as f:
        # Her satırı oku, boşlukları kaldır ve boş satırları filtrele
        bigg_ids = [line.strip() for line in f if line.strip()]

    if not bigg_ids:
        print(f"WARNING: No BiGG IDs found in '{bigg_id_list_file}'. Nothing to download.")
        return

    print(f"Found {len(bigg_ids)} BiGG IDs to download.")
    print(f"Downloading models into '{output_directory}'...")

    for i, bigg_id in enumerate(bigg_ids):
        print(f"\nProcessing {i+1}/{len(bigg_ids)}: {bigg_id}")
        download_sbml_model(bigg_id, output_directory, model_format='xml')
        
        # Son modelden sonra gecikme yapmaya gerek yok
        if i < len(bigg_ids) - 1:
            time.sleep(delay_between_requests)

    print("\nAll download attempts completed.")
    print(f"Please check the '{output_directory}' directory for the downloaded and renamed SBML files.")

if __name__ == "__main__":
    main()