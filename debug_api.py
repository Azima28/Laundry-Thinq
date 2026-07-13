import main
import sys

print("App imported")
try:
    with main.app.test_client() as client:
        print("Fetching /api/logs...")
        response = client.get('/api/logs')
        print(f"Status Code: {response.status_code}")
        print("Response Data:")
        print(response.get_data(as_text=True))
except Exception as e:
    print(f"Error occurred: {e}")
    import traceback
    traceback.print_exc()
