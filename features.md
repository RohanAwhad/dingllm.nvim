# ToDos

- [ ] Load and use docstrings.json to create a files.txt

### 009_Selecting Files for generation

Problem Definition: The user needs a function that will basically use llm to select all the files which are necessary for the actual coding based on the feature request information that is present in the context, because manually selecting files for context doesn't scale well.

User Story:
- User adds information about their feature like this: Problem Definition, and the User story
- Calls a function that reads the context above the cursor and calls an LLM with it.
- The llm is prompted to generate a list of files that it will need as context to implement the feature.
- The user will then copy paste these files into the files.txt and call the implement function (which is already present for now)



