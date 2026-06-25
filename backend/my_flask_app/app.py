from flask import Flask

# Initialize the Flask application
app = Flask(__name__)

# Define the route for the home page
@app.route("/")
def hello_world():
    return "<h1>Hello, World!</h1>"

if __name__ == "__main__":
    app.run(debug=True)
